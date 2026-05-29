import Combine
import Foundation
import IOKit.hid
import os

@MainActor
final class InputMonitoringCapability: Capability {
    let displayName = "Input Monitoring"
    let setupInstructions: String? =
        "Open System Settings → Privacy & Security → Input Monitoring, click +, add /Applications/FreeFlow.app, and toggle it on. Then click Refresh permission status below — if it still shows Not granted, quit and relaunch Free Flow."

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
        SystemSettingsPane.inputMonitoring.open()
    }

    private func update(_ next: CapabilityStatus) {
        guard subject.value != next else { return }
        logger.info("Input Monitoring status -> \(String(describing: next), privacy: .public)")
        subject.send(next)
    }

    /// `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` is the documented,
    /// non-prompting status check for Input Monitoring. It returns a true
    /// tri-state that maps 1:1 onto `CapabilityStatus`, so there is no guessing.
    /// We deliberately do NOT probe by creating a throwaway `CGEventTap`:
    /// `CGEvent.tapCreate` is owned solely by this capability's dedicated
    /// `com.freeflow.eventtap` background thread (landed in M4), and a probe on
    /// the main run loop would violate the threading invariant
    /// (threading-invariant.md, one-source-of-truth).
    private static func readStatus() -> CapabilityStatus {
        map(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
    }

    /// `kIOHIDAccessTypeUnknown` (never determined for this code signature) stays
    /// `.unknown` rather than being lowered to `.granted` — see capabilities.md
    /// "no lying". Internal for deterministic testing (the OS call above can't be
    /// exercised in CI).
    static func map(_ access: IOHIDAccessType) -> CapabilityStatus {
        if access == kIOHIDAccessTypeGranted { return .granted }
        if access == kIOHIDAccessTypeDenied { return .denied }
        return .unknown
    }
}
