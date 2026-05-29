import AppKit
import AVFoundation
import Combine
import Foundation
import os

@MainActor
final class MicrophoneCapability: Capability {
    let displayName = "Microphone"

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "permissions")
    private let subject: CurrentValueSubject<CapabilityStatus, Never>

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    init() {
        subject = CurrentValueSubject(Self.readStatus())
    }

    func recheck() async {
        updateStatus(Self.readStatus())
    }

    /// Microphone is the one permission macOS lets us auto-prompt for. After the
    /// user answers the system dialog, re-read the authoritative status.
    func requestGrant() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        logger.info("Microphone access request resolved: granted=\(granted, privacy: .public)")
        await recheck()
    }

    func openSystemSettings() {
        SystemSettingsPane.microphone.open()
    }

    private func updateStatus(_ next: CapabilityStatus) {
        guard subject.value != next else { return }
        logger.info("Microphone status -> \(String(describing: next), privacy: .public)")
        subject.send(next)
    }

    private static func readStatus() -> CapabilityStatus {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    // `.notDetermined` honestly maps to `.unknown`: we have not asked yet, so we
    // cannot claim either grant or denial. Lowering it to `.denied` would mislabel
    // a promptable state as a hard refusal. Internal for deterministic testing.
    static func map(_ status: AVAuthorizationStatus) -> CapabilityStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }
}
