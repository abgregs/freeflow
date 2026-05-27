import AppKit
import Combine
import Foundation

@MainActor
final class InputMonitoringCapability: Capability {
    let displayName = "Input Monitoring"
    private let subject = CurrentValueSubject<CapabilityStatus, Never>(.unknown)

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    func recheck() async {}

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
