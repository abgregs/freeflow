import AppKit
import Combine
import Foundation
import SwiftUI
import os

/// Owns launch-UI orchestration: the onboarding gate, the window's construction
/// and dismissal, and the runtime subscription that re-opens the window when a
/// capability's status degrades (e.g., M7's silent-no-op detector flips
/// `AccessibilityCapability.status` from `.granted` to `.denied`). Keeps
/// `AppDelegate` as the documented "thin lifecycle shell" by hosting the
/// publisher subscriptions and `NSWindow` lifetime that would otherwise
/// accumulate there.
@MainActor
final class OnboardingCoordinator {
    private let capabilities: [any Capability]
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "permissions")
    private var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private var lastSeenStatus: [ObjectIdentifier: CapabilityStatus] = [:]

    init(capabilities: [any Capability]) {
        self.capabilities = capabilities
    }

    /// Subscribes to every capability's status publisher so a `.granted →
    /// !.granted` transition re-presents onboarding mid-session. Idempotent.
    func start() {
        guard subscriptions.isEmpty else { return }
        for capability in capabilities {
            lastSeenStatus[ObjectIdentifier(capability)] = capability.currentStatus
            capability.status
                .sink { [weak self, weak capability] status in
                    guard let self, let capability else { return }
                    self.handleStatusChange(for: capability, newStatus: status)
                }
                .store(in: &subscriptions)
        }
    }

    /// Opens the window if the capability set is incomplete; otherwise no-op.
    /// Re-entrant: clicking through a partial grant and calling again finds the
    /// remaining permission and re-opens.
    func presentIfNeeded() {
        guard OnboardingGate.shouldPresent(for: capabilities) else { return }
        present()
    }

    // The runtime degradation hook. The `.granted → !.granted` transition is the
    // one that matters: it's how the M7 silent-no-op detector reaches the user
    // even after the launch-time gate let them through. A `.denied → .granted`
    // transition is handled by the user re-clicking Refresh in the onboarding
    // view itself, not by this coordinator.
    private func handleStatusChange(for capability: any Capability, newStatus: CapabilityStatus) {
        let key = ObjectIdentifier(capability)
        let previous = lastSeenStatus[key]
        lastSeenStatus[key] = newStatus
        guard previous == .granted, newStatus != .granted else { return }
        logger.warning("\(capability.displayName, privacy: .public) regressed from granted to \(String(describing: newStatus), privacy: .public); re-opening onboarding.")
        present()
    }

    private func present() {
        if let existing = window {
            activate(existing)
            return
        }
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Welcome to Free Flow"
        newWindow.contentViewController = NSHostingController(
            rootView: OnboardingView(capabilities: capabilities) { [weak self] in
                self?.dismiss()
            }
        )
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        window = newWindow
        activate(newWindow)
    }

    /// `LSUIElement` apps stay `.accessory` (no Dock icon). An accessory app can
    /// still key a window — flipping to `.regular` is unnecessary and adds a
    /// transient Dock icon. `ignoringOtherApps` + `orderFrontRegardless` is the
    /// minimal reliable way to surface a window from
    /// `applicationDidFinishLaunching` or from a background status change.
    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}
