import Foundation

@MainActor
final class HotkeyManager {
    private let inputMonitoring: InputMonitoringCapability

    init(inputMonitoring: InputMonitoringCapability) {
        self.inputMonitoring = inputMonitoring
    }
}
