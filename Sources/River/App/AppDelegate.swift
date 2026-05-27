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

    private(set) lazy var session: RiverSession = {
        RiverSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: HotkeyManager(inputMonitoring: inputMonitoring),
            audio: AudioCaptureManager(microphone: microphone),
            textInsertion: TextInsertionManager(accessibility: accessibility),
            transcription: TranscriptionService(),
            settings: settings
        )
    }()

    private var onboardingWindow: NSWindow?

    var capabilities: [any Capability] { [accessibility, microphone, inputMonitoring] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application did finish launching")
        Task { @MainActor in
            do { try await session.start() }
            catch { logger.error("Failed to start session: \(error.localizedDescription)") }
            presentOnboardingIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in await session.stop() }
    }

    private func presentOnboardingIfNeeded() {
        guard capabilities.contains(where: { $0.currentStatus != .granted }) else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to River"
        window.contentViewController = NSHostingController(rootView: OnboardingView(capabilities: capabilities))
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
