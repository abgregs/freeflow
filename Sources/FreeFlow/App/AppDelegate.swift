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

    private(set) lazy var session: FreeFlowSession = {
        FreeFlowSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: HotkeyManager(
                inputMonitoring: inputMonitoring,
                initialKeyCode: settings.value(for: Settings.activationKeyCode)
            ),
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
            for capability in capabilities { await capability.recheck() }
            presentOnboardingIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in await session.stop() }
    }

    private func presentOnboardingIfNeeded() {
        guard OnboardingGate.shouldPresent(for: capabilities) else { return }
        presentOnboardingWindow()
    }

    private func presentOnboardingWindow() {
        if let existing = onboardingWindow {
            activate(existing)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Free Flow"
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(capabilities: capabilities) { [weak self] in
                self?.dismissOnboarding()
            }
        )
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        activate(window)
    }

    /// `LSUIElement` apps stay `.accessory` (no Dock icon). An accessory app can
    /// still key a window — flipping to `.regular` is unnecessary and adds a
    /// transient Dock icon. `ignoringOtherApps` + `orderFrontRegardless` is the
    /// minimal reliable way to surface a window from `applicationDidFinishLaunching`.
    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }
}
