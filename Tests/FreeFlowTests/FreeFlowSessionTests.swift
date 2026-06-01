import Combine
import CoreGraphics
import Foundation
import Testing
@testable import FreeFlow

@Suite("FreeFlowSession")
struct FreeFlowSessionTests {
    @MainActor
    @Test("start leaves state idle and is idempotent")
    func startIsIdempotentNoOpCycle() async throws {
        let env = makeSession()
        #expect(env.session.currentState == .idle)
        try await env.session.start()
        #expect(env.session.currentState == .idle)
        try await env.session.start()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("stop is idempotent")
    func stopIsIdempotent() async throws {
        let env = makeSession()
        try await env.session.start()
        await env.session.stop()
        await env.session.stop()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("state publisher emits .idle on subscribe")
    func statePublisherEmitsIdleInitially() {
        // UI surfaces (menu bar, Settings) observe via the state publisher.
        // A subscriber must receive the current value immediately on subscribe.
        let env = makeSession()
        var received: [FreeFlowState] = []
        let token = env.session.state.sink { received.append($0) }
        defer { token.cancel() }
        #expect(received == [.idle])
    }

    @MainActor
    @Test("start subscribes to configuration publishers")
    func startSubscribesToConfiguration() async throws {
        // The activationKeyCode publisher (a CurrentValueSubject) emits its
        // current value to a new subscriber — exactly the live-apply semantic
        // (apply the current setting on launch).
        let env = makeSession()
        #expect(env.session.configurationApplyCount == 0)
        try await env.session.start()
        #expect(env.session.configurationApplyCount == 1)
    }

    @MainActor
    @Test("settings change while idle applies immediately")
    func settingsChangeWhileIdleApplies() async throws {
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount
        env.store.setValue(59, for: Settings.activationKeyCode)  // Left Control
        #expect(env.session.configurationApplyCount == baseline + 1)
        #expect(env.session.configurationDeferCount == 0)
    }

    @MainActor
    @Test("stop cancels configuration subscriptions")
    func stopCancelsSubscriptions() async throws {
        // A torn-down session must not keep reacting to live-apply events,
        // otherwise the deferral contract leaks across stop/start cycles.
        let env = makeSession()
        try await env.session.start()
        let afterStart = env.session.configurationApplyCount
        await env.session.stop()
        env.store.setValue(54, for: Settings.activationKeyCode)  // Right Command
        #expect(env.session.configurationApplyCount == afterStart)
    }

    @MainActor
    @Test("synthetic flagsChanged for watched key drives .idle → .recording → .idle")
    func endToEndStateTransitionsViaCombine() async throws {
        // M4 exit criterion: holding Right Control transitions the session to
        // .recording; releasing transitions back to .idle. Driven through the
        // full Combine chain (capability → manager → session) via the
        // capability's `publishForTest` seam — no real CGEventTap.
        let env = makeSession()
        env.session.wireHotkeyCallbacks()
        env.hotkey.bindEventStream()

        env.inputMonitoring.publishForTest(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(env.session.currentState == .recording)

        env.inputMonitoring.publishForTest(.flagsChanged(keyCode: 62, flags: []))
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("handleActivate is a no-op outside .idle")
    func handleActivateRejectsNonIdle() {
        // FreeFlowSession is the single writer of FreeFlowState; out-of-order
        // activations must log and return, never mutate the state machine.
        let env = makeSession()
        env.session.handleActivate()  // .idle → .recording
        #expect(env.session.currentState == .recording)
        env.session.handleActivate()  // .recording → ignored
        #expect(env.session.currentState == .recording)
    }

    @MainActor
    @Test("handleDeactivate is a no-op outside .recording")
    func handleDeactivateRejectsNonRecording() {
        let env = makeSession()
        env.session.handleDeactivate()  // .idle → ignored
        #expect(env.session.currentState == .idle)
    }

    // MARK: - Test environment

    @MainActor
    private struct TestEnv {
        let session: FreeFlowSession
        let store: SettingsStore
        let hotkey: HotkeyManager
        let inputMonitoring: InputMonitoringCapability
    }

    @MainActor
    private func makeSession() -> TestEnv {
        let accessibility = AccessibilityCapability()
        let microphone = MicrophoneCapability()
        let inputMonitoring = InputMonitoringCapability()
        let hotkey = HotkeyManager(inputMonitoring: inputMonitoring, initialKeyCode: 62)
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let session = FreeFlowSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: hotkey,
            audio: AudioCaptureManager(microphone: microphone),
            textInsertion: TextInsertionManager(accessibility: accessibility),
            transcription: TranscriptionService(),
            settings: store
        )
        return TestEnv(session: session, store: store, hotkey: hotkey, inputMonitoring: inputMonitoring)
    }
}
