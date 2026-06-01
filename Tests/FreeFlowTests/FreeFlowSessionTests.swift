import Combine
import Foundation
import Testing
@testable import FreeFlow

@Suite("FreeFlowSession")
struct FreeFlowSessionTests {
    @MainActor
    @Test("start leaves state idle and is idempotent")
    func startIsIdempotentNoOpCycle() async throws {
        let (session, _) = makeSession()
        #expect(session.currentState == .idle)
        try await session.start()
        #expect(session.currentState == .idle)
        try await session.start()
        #expect(session.currentState == .idle)
    }

    @MainActor
    @Test("stop is idempotent")
    func stopIsIdempotent() async throws {
        let (session, _) = makeSession()
        try await session.start()
        await session.stop()
        await session.stop()
        #expect(session.currentState == .idle)
    }

    @MainActor
    @Test("state publisher emits .idle on subscribe")
    func statePublisherEmitsIdleInitially() {
        // UI surfaces (menu bar, Settings) observe via the state publisher.
        // A subscriber must receive the current value immediately on subscribe.
        let (session, _) = makeSession()
        var received: [FreeFlowState] = []
        let token = session.state.sink { received.append($0) }
        defer { token.cancel() }
        #expect(received == [.idle])
    }

    @MainActor
    @Test("start subscribes to configuration publishers")
    func startSubscribesToConfiguration() async throws {
        // The placeholder publisher (a CurrentValueSubject) emits its current
        // value to a new subscriber — exactly the live-apply semantic M8 needs
        // (apply the current setting on launch).
        let (session, _) = makeSession()
        #expect(session.configurationApplyCount == 0)
        try await session.start()
        #expect(session.configurationApplyCount == 1)
    }

    @MainActor
    @Test("settings change while idle applies immediately")
    func settingsChangeWhileIdleApplies() async throws {
        let (session, store) = makeSession()
        try await session.start()
        let baseline = session.configurationApplyCount
        store.setValue(42, for: Settings.m1Placeholder)
        #expect(session.configurationApplyCount == baseline + 1)
        #expect(session.configurationDeferCount == 0)
    }

    @MainActor
    @Test("stop cancels configuration subscriptions")
    func stopCancelsSubscriptions() async throws {
        // A torn-down session must not keep reacting to live-apply events,
        // otherwise the deferral contract leaks across stop/start cycles.
        let (session, store) = makeSession()
        try await session.start()
        let afterStart = session.configurationApplyCount
        await session.stop()
        store.setValue(99, for: Settings.m1Placeholder)
        #expect(session.configurationApplyCount == afterStart)
    }

    @MainActor
    private func makeSession() -> (FreeFlowSession, SettingsStore) {
        let accessibility = AccessibilityCapability()
        let microphone = MicrophoneCapability()
        let inputMonitoring = InputMonitoringCapability()
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let session = FreeFlowSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: HotkeyManager(inputMonitoring: inputMonitoring),
            audio: AudioCaptureManager(microphone: microphone),
            textInsertion: TextInsertionManager(accessibility: accessibility),
            transcription: TranscriptionService(),
            settings: store
        )
        return (session, store)
    }
}
