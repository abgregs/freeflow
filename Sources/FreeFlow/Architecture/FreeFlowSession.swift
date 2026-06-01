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
        logger.info("FreeFlowSession started")
    }

    func stop() async {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        logger.info("FreeFlowSession stopped")
    }

    // M1 placeholder subscription as the M8 wiring template — see configuration.md.
    private func subscribeToConfiguration() {
        settings.publisher(for: Settings.m1Placeholder)
            .sink { [weak self] _ in
                self?.applyOrDeferReconfiguration { /* placeholder has no consumer */ }
            }
            .store(in: &cancellables)
    }

    // Structural deferral — anti-pattern #7. Pending apply on return to idle lands in M8.
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
