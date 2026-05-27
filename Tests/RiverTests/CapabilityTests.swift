import Testing
@testable import River

@Suite("Capabilities")
struct CapabilityTests {
    @MainActor
    @Test("AccessibilityCapability reports .unknown after init and recheck")
    func accessibilityUnknown() async throws {
        let capability = AccessibilityCapability()
        #expect(capability.currentStatus == .unknown)
        await capability.recheck()
        #expect(capability.currentStatus == .unknown)
    }

    @MainActor
    @Test("MicrophoneCapability reports .unknown after init and recheck")
    func microphoneUnknown() async throws {
        let capability = MicrophoneCapability()
        #expect(capability.currentStatus == .unknown)
        await capability.recheck()
        #expect(capability.currentStatus == .unknown)
    }

    @MainActor
    @Test("InputMonitoringCapability reports .unknown after init and recheck")
    func inputMonitoringUnknown() async throws {
        let capability = InputMonitoringCapability()
        #expect(capability.currentStatus == .unknown)
        await capability.recheck()
        #expect(capability.currentStatus == .unknown)
    }
}
