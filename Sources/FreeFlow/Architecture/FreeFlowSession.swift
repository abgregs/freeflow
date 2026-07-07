import AppKit
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
    private let mediaPause: MediaPauseManager
    private let settings: SettingsStore

    // The most recent successful transcription, retained in memory for user-initiated
    // recovery (planning 0019). Set on transcription success — including when the paste
    // then fails, which is the recovery case (AC1). Never persisted, never logged.
    // `didSet` keeps the availability subject in sync.
    private var lastTranscript: String? {
        didSet { lastTranscriptAvailableSubject.send(lastTranscript != nil) }
    }
    private let lastTranscriptAvailableSubject = CurrentValueSubject<Bool, Never>(false)

    private var isStarted = false
    private var cancellables = Set<AnyCancellable>()
    // A list, not a single slot: two settings (key + mode) can both be deferred
    // during one Hold recording or `.processing` window, and both must apply on
    // the return to `.idle` — a single slot would drop the earlier one.
    private var pendingReconfigurations: [() -> Void] = []
    // A single slot, not a list: a model switch replaces the whole model, so only
    // the latest selection matters — collapsing A→B→C during one cycle to just C
    // avoids reloading models the user already moved past.
    private var pendingModelSwitch: (() -> Void)?
    // The mode driving the current recording — decides whether a mid-recording
    // key/mode change applies live (tap modes) or is deferred (Hold).
    private var activeMode: ActivationMode = Constants.defaultActivationMode

    // internal for testability — tests assert subscription wiring through the
    // counters rather than inspecting the handler closures.
    private(set) var configurationApplyCount = 0
    private(set) var configurationDeferCount = 0
    // Separate counters for the model-switch path (planning 0021): it shares the
    // apply-or-defer contract but never the tap-mode live branch, and keeping it off
    // the hotkey counters keeps each path's tests independent.
    private(set) var modelReloadApplyCount = 0
    private(set) var modelReloadDeferCount = 0

    var state: AnyPublisher<FreeFlowState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentState: FreeFlowState { stateSubject.value }
    // The cycle-failure surface for the menu bar (and, later, the recording HUD
    // — planning 0002). Lands with a renderer per free-flow-pipeline.md.
    var errors: AnyPublisher<FreeFlowError, Never> { errorSubject.eraseToAnyPublisher() }
    // Recording-context notices (e.g. "activation key changed — press it to stop").
    // Same observers as `errors`; shown in the menu bar now, the HUD later.
    var notices: AnyPublisher<String, Never> { noticeSubject.eraseToAnyPublisher() }
    // Availability signal for the "Copy Last Transcription" menu item (planning 0019).
    // Emits `true` after the first successful transcription; `AppState` bridges it.
    var lastTranscriptAvailable: AnyPublisher<Bool, Never> { lastTranscriptAvailableSubject.eraseToAnyPublisher() }
    // internal for testability — availability only, never the content.
    var hasLastTranscript: Bool { lastTranscript != nil }

    init(
        accessibility: AccessibilityCapability,
        microphone: MicrophoneCapability,
        inputMonitoring: InputMonitoringCapability,
        hotkey: HotkeyManager,
        audio: AudioCaptureManager,
        textInsertion: TextInsertionManager,
        transcription: TranscriptionManager,
        mediaPause: MediaPauseManager,
        settings: SettingsStore
    ) {
        self.accessibility = accessibility
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.hotkey = hotkey
        self.audio = audio
        self.textInsertion = textInsertion
        self.transcription = transcription
        self.mediaPause = mediaPause
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

    /// Writes the last retained transcription to the general pasteboard.
    /// No-op when no transcription has been retained yet.
    ///
    /// User-initiated only — the automated insertion cycle never touches the
    /// clipboard (planning 0011). Applies nspasteboard.org marker types so
    /// well-behaved clipboard managers skip recording the dictated content.
    func copyLastTranscript() {
        guard let text = lastTranscript else { return }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for rawType in Constants.pasteboardMarkerTypes {
            item.setData(Data(), forType: NSPasteboard.PasteboardType(rawType))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        // Content is never logged — only its count; see logging.md anti-pattern #4.
        logger.info("Copied last transcript to pasteboard (\(text.count, privacy: .public) chars)")
    }

    // internal for testability — wires hotkey callbacks without starting the
    // real tap, so tests can drive the chain via `InputMonitoringCapability.publishForTest`.
    func wireHotkeyCallbacks() {
        hotkey.onActivate = { [weak self] in self?.handleActivate() }
        hotkey.onDeactivate = { [weak self] in
            Task { @MainActor in await self?.handleDeactivate() }
        }
        hotkey.onCancel = { [weak self] in self?.handleCancel() }
    }

    // internal for testability — state-guarded `.idle` → `.recording` transition.
    // Audio capture is kicked off fire-and-forget so the state change is
    // immediately observable; engine-warmup race is handled at stop time.
    //
    // If the model is not yet ready the activation is declined and an error is
    // surfaced immediately (planning 0004 AC3) — no audio is captured, so no
    // audio can be silently lost to the `.modelNotLoaded` fail-fast.
    func handleActivate() {
        guard currentState == .idle else {
            logger.info("Ignoring activate in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        guard transcription.currentModelLoadState == .ready else {
            logger.info("Ignoring activate: model not ready (\(String(describing: self.transcription.currentModelLoadState), privacy: .public))")
            errorSubject.send(.transcription(underlying: TranscriptionError.modelNotLoaded))
            return
        }
        stateSubject.send(.recording)
        logger.info("State -> recording")
        // Pause now-playing media when the setting is on. pauseIfPlaying() is
        // fire-and-forget (reads state via async MediaRemote callback). The begin
        // sound cue fires concurrently via AppState observation; in practice the
        // cue plays first (NSSound schedules synchronously) and media pauses
        // shortly after — acceptable per planning 0003.
        if settings.value(for: Settings.pauseMediaWhileDictating) {
            mediaPause.pauseIfPlaying()
        }
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
            if samples.isEmpty {
                // Buffers arrived but the silence trim removed everything: an
                // all-silence recording (a stray key-brush, an accidental tap). The
                // user said nothing — NOT a failure. Drop silently: don't decode
                // (Whisper hallucinates text from silence), don't paste, don't raise
                // the error glyph. The `notices` channel clears on recording-end
                // (AppState) so a post-recording message wouldn't survive there, and
                // a stray brush shouldn't nag; logged for observability (planning
                // 0023). A recording that DID contain speech but decoded empty still
                // throws `.emptyTranscription` below and surfaces loudly.
                logger.info("Recording was all silence after trim; skipping decode")
            } else {
                do {
                    let text = try await transcription.transcribe(audioSamples: samples)
                    logger.info("Transcribed \(text.count, privacy: .public) chars")
                    // Retain before the paste attempt: recovery is available even
                    // when insertion fails (planning 0019 AC1). Content is never
                    // logged — only its count is; see logging.md anti-pattern #4.
                    lastTranscript = text
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
            }
        } catch {
            logger.error("Audio capture failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            errorSubject.send(.audioCapture(underlying: error))
        }
        stateSubject.send(.idle)
        logger.info("State -> idle")
        mediaPause.resumeIfPaused()
        applyPendingReconfigurations()
        applyPendingModelSwitch()
    }

    // internal for testability — the discard transition (planning 0017):
    // `.recording → .idle` with NO transcription and NO paste. Guarded to
    // `.recording`, mirroring the re-entrancy posture of `handleActivate` /
    // `handleDeactivate`, so cancel while `.idle` or `.processing` is a logged
    // no-op (cancel during `.processing` is out of scope — the paste is imminent).
    // The audio buffers are discarded (never converted); a `notices` message makes
    // the cancel visible. Crucially it runs the SAME deferral loop as the normal
    // cycle end, so a key/mode/model change parked during the canceled recording
    // still applies on the return to `.idle` (AC3). The notice is sent AFTER the
    // `.idle` transition: `AppState` clears recording-context notices on leaving
    // `.recording`, so emitting first would immediately wipe it.
    func handleCancel() {
        guard currentState == .recording else {
            logger.info("Ignoring cancel in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        logger.info("Cancel: discarding in-flight recording (no transcription, no paste)")
        let audio = self.audio
        Task { @MainActor in await audio.discardRecording() }
        stateSubject.send(.idle)
        logger.info("State -> idle (canceled)")
        mediaPause.resumeIfPaused()
        noticeSubject.send(ActivationNotice.recordingCanceled)
        applyPendingReconfigurations()
        applyPendingModelSwitch()
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
        settings.publisher(for: Settings.selectedModel)
            .sink { [weak self] newModel in self?.reconfigureModel(newModel) }
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

    // Model-switch reconfiguration (planning 0021). Mirrors the hotkey apply-or-defer
    // contract, minus the tap-mode live branch: reloading the model mid-recording
    // would swap `whisperKit` out from under the pending `.processing` transcribe, so
    // a switch is only ever applied at `.idle` — immediately when idle, or on the
    // deferred return to `.idle` otherwise. The manager re-enters the 0004 load states
    // during the reload, so the menu bar shows the switch rather than a false "Ready."
    private func reconfigureModel(_ newModel: String) {
        switch currentState {
        case .idle:
            applyModelSwitch(newModel)
            modelReloadApplyCount += 1
        case .recording, .processing:
            pendingModelSwitch = { [weak self] in self?.applyModelSwitch(newModel) }
            modelReloadDeferCount += 1
        }
    }

    private func applyModelSwitch(_ newModel: String) {
        let transcription = self.transcription
        Task { @MainActor in await transcription.switchModel(to: newModel) }
    }

    // Fires the parked model switch on the return to `.idle`, closing the same
    // deferral loop as `applyPendingReconfigurations` for the model path.
    private func applyPendingModelSwitch() {
        guard let pending = pendingModelSwitch else { return }
        pendingModelSwitch = nil
        pending()
        modelReloadApplyCount += 1
    }
}
