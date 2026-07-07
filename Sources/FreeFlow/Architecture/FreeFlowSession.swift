import Combine
import Foundation
import os

// Cycle-failure surface, one case per stage; redact the message before display (ADR 0002).
enum FreeFlowError: LocalizedError {
    case audioCapture(underlying: Error)
    case transcription(underlying: Error)
    case textInsertion(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .audioCapture(let underlying): return "Couldn't capture audio: \(underlying.localizedDescription)"
        case .transcription(let underlying): return "Couldn't transcribe: \(underlying.localizedDescription)"
        case .textInsertion(let underlying): return "Couldn't paste: \(underlying.localizedDescription)"
        }
    }
}

@MainActor
final class FreeFlowSession {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")
    private let stateSubject = CurrentValueSubject<FreeFlowState, Never>(.idle)
    private let errorSubject = PassthroughSubject<FreeFlowError, Never>()
    private let noticeSubject = PassthroughSubject<String, Never>()

    private let accessibility: AccessibilityCapability
    private let microphone: MicrophoneCapability
    private let inputMonitoring: InputMonitoringCapability
    private let hotkey: HotkeyManager
    private let audio: AudioCaptureManager
    private let textInsertion: TextInsertionManager
    private let transcription: TranscriptionManager
    private let settings: SettingsStore

    private var isStarted = false
    private var cancellables = Set<AnyCancellable>()
    // A list, not a single slot: two settings (key + mode) can both be deferred
    // during one Hold recording or `.processing` window, and both must apply on
    // the return to `.idle` — a single slot would drop the earlier one.
    private var pendingReconfigurations: [() -> Void] = []
    // The mode driving the current recording — decides whether a mid-recording
    // key/mode change applies live (tap modes) or is deferred (Hold).
    private var activeMode: ActivationMode = Constants.defaultActivationMode

    // internal for testability — tests assert subscription wiring through the
    // counters rather than inspecting the handler closures.
    private(set) var configurationApplyCount = 0
    private(set) var configurationDeferCount = 0

    var state: AnyPublisher<FreeFlowState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentState: FreeFlowState { stateSubject.value }
    // The cycle-failure surface for the menu bar (and, later, the recording HUD
    // — planning 0002). Lands with a renderer per free-flow-pipeline.md.
    var errors: AnyPublisher<FreeFlowError, Never> { errorSubject.eraseToAnyPublisher() }
    // Recording-context notices (e.g. "activation key changed — press it to stop").
    // Same observers as `errors`; shown in the menu bar now, the HUD later.
    var notices: AnyPublisher<String, Never> { noticeSubject.eraseToAnyPublisher() }

    init(
        accessibility: AccessibilityCapability,
        microphone: MicrophoneCapability,
        inputMonitoring: InputMonitoringCapability,
        hotkey: HotkeyManager,
        audio: AudioCaptureManager,
        textInsertion: TextInsertionManager,
        transcription: TranscriptionManager,
        settings: SettingsStore
    ) {
        self.accessibility = accessibility
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.hotkey = hotkey
        self.audio = audio
        self.textInsertion = textInsertion
        self.transcription = transcription
        self.settings = settings
    }

    func start() async throws {
        guard !isStarted else { return }
        isStarted = true
        subscribeToConfiguration()
        wireHotkeyCallbacks()
        await hotkey.start()
        logger.info("FreeFlowSession started")
    }

    func stop() async {
        guard isStarted else { return }
        isStarted = false
        await hotkey.stop()
        cancellables.removeAll()
        logger.info("FreeFlowSession stopped")
    }

    // internal for testability — wires hotkey callbacks without starting the
    // real tap, so tests can drive the chain via `InputMonitoringCapability.publishForTest`.
    func wireHotkeyCallbacks() {
        hotkey.onActivate = { [weak self] in self?.handleActivate() }
        hotkey.onDeactivate = { [weak self] in
            Task { @MainActor in await self?.handleDeactivate() }
        }
    }

    // internal for testability — state-guarded `.idle` → `.recording` transition.
    // Audio capture is kicked off fire-and-forget so the state change is
    // immediately observable; engine-warmup race is handled at stop time.
    func handleActivate() {
        guard currentState == .idle else {
            logger.info("Ignoring activate in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        stateSubject.send(.recording)
        logger.info("State -> recording")
        let audio = self.audio
        Task { @MainActor in await audio.startRecording() }
    }

    // internal for testability — full cycle: `.recording` → `.processing` →
    // capture/convert/transcribe/paste → `.idle`. Async so tests can `await`
    // the complete cycle. Each step's failure is caught independently so the
    // cycle always returns to `.idle` and pending reconfiguration applies;
    // getting stuck in `.processing` would freeze the app (free-flow-pipeline.md).
    func handleDeactivate() async {
        guard currentState == .recording else {
            logger.info("Ignoring deactivate in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        stateSubject.send(.processing)
        logger.info("State -> processing")
        do {
            let samples = try await audio.stopRecording()
            logger.info("Captured \(samples.count, privacy: .public) samples")
            do {
                let text = try await transcription.transcribe(audioSamples: samples)
                logger.info("Transcribed \(text.count, privacy: .public) chars")
                do {
                    try await textInsertion.insertText(text)
                } catch {
                    logger.error("Text insertion failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
                    errorSubject.send(.textInsertion(underlying: error))
                }
            } catch {
                logger.error("Transcription failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
                errorSubject.send(.transcription(underlying: error))
            }
        } catch {
            logger.error("Audio capture failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            errorSubject.send(.audioCapture(underlying: error))
        }
        stateSubject.send(.idle)
        logger.info("State -> idle")
        applyPendingReconfigurations()
    }

    // Pending reconfigurations parked during a non-idle cycle fire on the
    // return to `.idle` — closes the deferral loop documented in
    // `architecture/free-flow-session.md` "Reconfiguration without leaks".
    private func applyPendingReconfigurations() {
        guard !pendingReconfigurations.isEmpty else { return }
        let pending = pendingReconfigurations
        pendingReconfigurations.removeAll()
        for apply in pending {
            apply()
            configurationApplyCount += 1
        }
    }

    // Subscribes to the activation publishers. Each change routes through
    // `reconfigureHotkey`, which applies live, defers, or notifies depending on
    // the cycle state and active mode.
    private func subscribeToConfiguration() {
        settings.publisher(for: Settings.activationKeyCode)
            .sink { [weak self] newCode in
                self?.reconfigureHotkey(notice: ActivationNotice.keyChanged(toKeyCode: newCode)) { [weak self] in
                    self?.hotkey.setActivationKeyCode(newCode)
                }
            }
            .store(in: &cancellables)
        settings.publisher(for: Settings.activationMode)
            .sink { [weak self] newMode in
                self?.reconfigureHotkey(notice: ActivationNotice.modeChanged(to: newMode)) { [weak self] in
                    self?.hotkey.setActivationMode(newMode)
                    self?.activeMode = newMode
                }
            }
            .store(in: &cancellables)
    }

    // Mode-dependent reconfiguration. Idle applies immediately. During a tap-mode
    // recording the change applies LIVE and the user is notified — switching the
    // key is a keycode refilter, not a tap teardown, so the running tap and the
    // captured audio both survive, and the new key/mode is the stop gesture the
    // user just chose. A Hold recording (the user is holding the old key, whose
    // release must stay watched) and any `.processing` state defer to the next
    // return to `.idle`. See architecture/free-flow-session.md.
    private func reconfigureHotkey(notice: @autoclosure () -> String, _ apply: @escaping () -> Void) {
        switch currentState {
        case .idle:
            apply()
            configurationApplyCount += 1
        case .recording where activeMode != .hold:
            apply()
            configurationApplyCount += 1
            noticeSubject.send(notice())
        case .recording, .processing:
            pendingReconfigurations.append(apply)
            configurationDeferCount += 1
        }
    }
}
