import Combine
import Foundation
import os

@MainActor
final class FreeFlowSession {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")
    private let stateSubject = CurrentValueSubject<FreeFlowState, Never>(.idle)

    private let accessibility: AccessibilityCapability
    private let microphone: MicrophoneCapability
    private let inputMonitoring: InputMonitoringCapability
    private let hotkey: HotkeyManager
    private let audio: AudioCaptureManager
    private let textInsertion: TextInsertionManager
    private let transcription: TranscriptionService
    private let settings: SettingsStore

    private var isStarted = false
    private var cancellables = Set<AnyCancellable>()
    private var pendingReconfiguration: (() -> Void)?

    // internal for testability — tests assert subscription wiring through the
    // counters rather than inspecting the handler closures.
    private(set) var configurationApplyCount = 0
    private(set) var configurationDeferCount = 0

    var state: AnyPublisher<FreeFlowState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentState: FreeFlowState { stateSubject.value }

    init(
        accessibility: AccessibilityCapability,
        microphone: MicrophoneCapability,
        inputMonitoring: InputMonitoringCapability,
        hotkey: HotkeyManager,
        audio: AudioCaptureManager,
        textInsertion: TextInsertionManager,
        transcription: TranscriptionService,
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
        hotkey.onDeactivate = { [weak self] in self?.handleDeactivate() }
    }

    // internal for testability — state-guarded `.idle` → `.recording` transition.
    // M5/M6 will start audio capture here; M4 is the wiring milestone.
    func handleActivate() {
        guard currentState == .idle else {
            logger.info("Ignoring activate in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        stateSubject.send(.recording)
        logger.info("State -> recording")
    }

    // internal for testability — state-guarded `.recording` → `.idle` transition.
    // M5 will route through `.processing` (transcribe + paste); M4 returns to idle directly.
    func handleDeactivate() {
        guard currentState == .recording else {
            logger.info("Ignoring deactivate in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        stateSubject.send(.idle)
        logger.info("State -> idle")
    }

    // Subscribes to the activation publishers. Each subscription routes through
    // `applyOrDeferReconfiguration` so a change during a non-idle cycle parks in
    // `pendingReconfiguration` (anti-pattern #7). M8 adds the mode publisher.
    private func subscribeToConfiguration() {
        settings.publisher(for: Settings.activationKeyCode)
            .sink { [weak self] newCode in
                self?.applyOrDeferReconfiguration { [weak self] in
                    self?.hotkey.setActivationKeyCode(newCode)
                }
            }
            .store(in: &cancellables)
    }

    // Structural deferral — anti-pattern #7. The pending closure runs on the
    // next return to `.idle` (wired in M5 alongside the real cycle transitions).
    private func applyOrDeferReconfiguration(_ apply: @escaping () -> Void) {
        if currentState == .idle {
            apply()
            configurationApplyCount += 1
        } else {
            pendingReconfiguration = apply
            configurationDeferCount += 1
        }
    }
}
