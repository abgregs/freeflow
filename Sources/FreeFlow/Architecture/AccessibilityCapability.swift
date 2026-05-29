import AppKit
import ApplicationServices
import Combine
import Foundation
import os

@MainActor
final class AccessibilityCapability: Capability {
    let displayName = "Accessibility"
    let setupInstructions: String? =
        "Open System Settings → Privacy & Security → Accessibility, click +, navigate to /Applications/FreeFlow.app, and toggle it on. Then quit and relaunch Free Flow."

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "permissions")
    private let subject: CurrentValueSubject<CapabilityStatus, Never>

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    init() {
        subject = CurrentValueSubject(Self.readStatus())
    }

    func recheck() async {
        update(Self.readStatus())
    }

    func openSystemSettings() {
        SystemSettingsPane.accessibility.open()
    }

    private func update(_ next: CapabilityStatus) {
        guard subject.value != next else { return }
        logger.info("Accessibility status -> \(String(describing: next), privacy: .public)")
        subject.send(next)
    }

    private static func readStatus() -> CapabilityStatus {
        map(isTrusted: AXIsProcessTrusted())
    }

    /// `AXIsProcessTrusted()` reports whether *this running process* is trusted,
    /// so a stale grant for a previous build reads as `.denied` honestly — there
    /// is no false `.granted`. The silent-no-op detector for the bundle-
    /// misidentification case lands with `postKeyEvent` in M7 (see capabilities.md).
    /// internal for testability (the OS call above can't be exercised in CI).
    static func map(isTrusted: Bool) -> CapabilityStatus {
        isTrusted ? .granted : .denied
    }
}
