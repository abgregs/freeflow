import Combine
import Foundation

enum CapabilityStatus: Equatable {
    case granted
    case denied
    case unknown
}

@MainActor
protocol Capability: AnyObject {
    var displayName: String { get }
    var status: AnyPublisher<CapabilityStatus, Never> { get }
    var currentStatus: CapabilityStatus { get }
    func recheck() async
    func openSystemSettings()
}
