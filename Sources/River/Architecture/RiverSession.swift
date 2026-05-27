import Combine
import Foundation
import os

@MainActor
final class RiverSession {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")
    private let stateSubject = CurrentValueSubject<RiverState, Never>(.idle)

    private let accessibility: AccessibilityCapability
    private let microphone: MicrophoneCapability
    private let inputMonitoring: InputMonitoringCapability
    private let hotkey: HotkeyManager
    private let audio: AudioCaptureManager
    private let textInsertion: TextInsertionManager
    private let transcription: TranscriptionService
    private let settings: SettingsStore

    private var isStarted = false

    var state: AnyPublisher<RiverState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentState: RiverState { stateSubject.value }

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
        logger.info("RiverSession started")
    }

    func stop() async {
        guard isStarted else { return }
        isStarted = false
        logger.info("RiverSession stopped")
    }
}
