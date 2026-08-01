import AppKit
import Foundation
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")

    let accessibility = AccessibilityCapability()
    let microphone = MicrophoneCapability()
    let inputMonitoring = InputMonitoringCapability()
    let settings = SettingsStore()
    let transcription = TranscriptionManager()
    let appState = AppState()

    private(set) lazy var session: FreeFlowSession = {
        FreeFlowSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: HotkeyManager(
                inputMonitoring: inputMonitoring,
                initialKeyCode: settings.value(for: Settings.activationKeyCode),
                initialMode: settings.value(for: Settings.activationMode)
            ),
            audio: AudioCaptureManager(microphone: microphone),
            textInsertion: TextInsertionManager(accessibility: accessibility),
            transcription: transcription,
            settings: settings
        )
    }()

    var capabilities: [any Capability] { [accessibility, microphone, inputMonitoring] }

    private(set) lazy var onboarding: OnboardingCoordinator = {
        OnboardingCoordinator(capabilities: capabilities)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application did finish launching")
        appState.bind(to: session)
        onboarding.start()
        Task { @MainActor in
            do { try await session.start() }
            catch { logger.error("Failed to start session: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)") }
            for capability in capabilities { await capability.recheck() }
            onboarding.presentIfNeeded()
        }
        // Model load is fire-and-forget on its own schedule (per the architecture:
        // "Default model loads on launch, not blocking the session"). First launch
        // may download the model; subsequent launches use the cached copy.
        Task { @MainActor in
            try? await transcription.loadModel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in await session.stop() }
    }
}
