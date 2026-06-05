import AVFoundation
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
        let env = makeSession()
        var received: [FreeFlowState] = []
        let token = env.session.state.sink { received.append($0) }
        defer { token.cancel() }
        #expect(received == [.idle])
    }

    @MainActor
    @Test("start subscribes to configuration publishers")
    func startSubscribesToConfiguration() async throws {
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
        env.store.setValue(59, for: Settings.activationKeyCode)
        #expect(env.session.configurationApplyCount == baseline + 1)
        #expect(env.session.configurationDeferCount == 0)
    }

    @MainActor
    @Test("stop cancels configuration subscriptions")
    func stopCancelsSubscriptions() async throws {
        let env = makeSession()
        try await env.session.start()
        let afterStart = env.session.configurationApplyCount
        await env.session.stop()
        env.store.setValue(54, for: Settings.activationKeyCode)
        #expect(env.session.configurationApplyCount == afterStart)
    }

    @MainActor
    @Test("activate via Combine + await deactivate drives a full .idle → .recording → .idle cycle")
    func endToEndCycleViaCombineAndDirectDeactivate() async throws {
        // Activate goes through the full chain (capability → manager → session)
        // synchronously because `hotkey.handle` runs on the publisher's actor.
        // Deactivate is async (it awaits stopRecording); the production callback
        // wraps it in a Task — tests call it directly to keep the assertion sync.
        let env = makeSession()
        env.session.wireHotkeyCallbacks()
        env.hotkey.bindEventStream()

        env.inputMonitoring.publishForTest(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(env.session.currentState == .recording)

        // Let the fire-and-forget startRecording Task subscribe to mic buffers
        // before we publish one.
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())

        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("state publisher records .recording → .processing → .idle through a cycle")
    func statePublisherRecordsFullSequence() async throws {
        // FreeFlowSession is the single writer of FreeFlowState; the publisher
        // is the only observable surface. The sequence below is the contract
        // M5 establishes (M4 skipped .processing entirely).
        let env = makeSession()
        var states: [FreeFlowState] = []
        let token = env.session.state.sink { states.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()

        #expect(states == [.idle, .recording, .processing, .idle])
    }

    @MainActor
    @Test("handleDeactivate still returns to .idle when stopRecording throws")
    func handleDeactivateReturnsToIdleOnAudioError() async throws {
        // No buffer published → stopRecording waits ~300 ms then throws
        // .noAudioCaptured. The session must log and still complete the cycle —
        // getting stuck in .processing would freeze the app.
        let env = makeSession()
        env.session.handleActivate()
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("handleDeactivate emits a cycle error and still returns to .idle when capture fails")
    func emitsCycleErrorOnAudioFailure() async throws {
        // Same no-buffer path as handleDeactivateReturnsToIdleOnAudioError, now
        // also asserting the session-level error publisher surfaces the failure
        // for the menu-bar renderer — and that the emission does not disturb the
        // guaranteed return to .idle.
        let env = makeSession()
        var errors: [FreeFlowError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        await env.session.handleDeactivate()

        #expect(env.session.currentState == .idle)
        #expect(errors.count == 1)
        guard case .audioCapture = errors.first else {
            Issue.record("expected .audioCapture, got \(String(describing: errors.first))")
            return
        }
    }

    @MainActor
    @Test("pending reconfiguration applies on return to .idle")
    func pendingReconfigurationAppliesOnReturnToIdle() async throws {
        // The M3 deferral slot closes here: a settings change during a cycle is
        // parked and applies cleanly when the cycle ends, with no path that
        // tears down the hotkey mid-recording (anti-pattern #7).
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount  // 1 from initial emit

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue(59, for: Settings.activationKeyCode)  // change while .recording
        #expect(env.session.configurationApplyCount == baseline)  // unchanged — deferred
        #expect(env.session.configurationDeferCount == 1)

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.session.configurationApplyCount == baseline + 1)  // pending applied
    }

    @MainActor
    @Test(.disabled("end-to-end paste verification requires a loaded WhisperKit model + Accessibility grant — manual on-device before release. The insertion-catch branch in handleDeactivate is structurally identical to the transcription-catch (which is already covered by handleDeactivateReturnsToIdleOnAudioError indirectly) — reaching it in a unit test would require injecting a success-path TranscriptionService fake, which ADR 0001 defers until a second adapter shows up."))
    func endToEndPasteCycle() async throws {
        // Placeholder lives here so the gap is locatable in the suite, not
        // hidden in a doc. If this comment grows to a third bullet, the ADR
        // revisit trigger has fired — extract a TranscriptionService protocol.
    }

    @MainActor
    @Test("handleActivate is a no-op outside .idle")
    func handleActivateRejectsNonIdle() {
        let env = makeSession()
        env.session.handleActivate()
        #expect(env.session.currentState == .recording)
        env.session.handleActivate()
        #expect(env.session.currentState == .recording)
    }

    @MainActor
    @Test("handleDeactivate is a no-op outside .recording")
    func handleDeactivateRejectsNonRecording() async {
        let env = makeSession()
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
    }

    // MARK: - Test environment

    @MainActor
    private struct TestEnv {
        let session: FreeFlowSession
        let store: SettingsStore
        let hotkey: HotkeyManager
        let inputMonitoring: InputMonitoringCapability
        let microphone: MicrophoneCapability
    }

    @MainActor
    private func makeSession() -> TestEnv {
        let accessibility = AccessibilityCapability()
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
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
        return TestEnv(
            session: session,
            store: store,
            hotkey: hotkey,
            inputMonitoring: inputMonitoring,
            microphone: microphone
        )
    }

    @MainActor
    private func makeBuffer(milliseconds: Int = 100, sampleRate: Double = 44_100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        )!
        let frames = AVAudioFrameCount(Double(milliseconds) * sampleRate / 1000.0)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return buffer
    }
}
