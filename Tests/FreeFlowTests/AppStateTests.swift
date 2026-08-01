import Foundation
import Testing
@testable import FreeFlow

@Suite("AppState")
struct AppStateTests {
    @MainActor
    @Test("state changes propagate to the observable")
    func stateChangesPropagate() {
        let appState = AppState()
        #expect(appState.state == .idle)
        appState.apply(.recording)
        #expect(appState.state == .recording)
    }

    @MainActor
    @Test("a cycle error becomes a path-redacted message")
    func errorBecomesRedactedMessage() throws {
        // The single choke point: a framework error naming a home path must not
        // carry the account name onto the menu (ADR 0002). If this regresses,
        // the username ships in a screenshot of the menu.
        let appState = AppState()
        let underlying = NSError(
            domain: "WhisperKit", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "load failed at /Users/alice/Documents/model.bin"]
        )
        appState.apply(FreeFlowError.transcription(underlying: underlying))
        let message = try #require(appState.errorMessage)
        #expect(message.contains("/Users/<user>/Documents/model.bin"))
        #expect(!message.contains("/Users/alice"))
    }

    @MainActor
    @Test("starting a new recording clears a stale error")
    func recordingClearsStaleError() {
        let appState = AppState()
        appState.apply(FreeFlowError.textInsertion(underlying: NSError(domain: "x", code: 1)))
        #expect(appState.errorMessage != nil)
        appState.apply(.recording)
        #expect(appState.errorMessage == nil)
    }

    @MainActor
    @Test("a recording-context notice shows during recording and clears when it ends")
    func noticeShownThenClearedOnRecordingEnd() {
        // The live-apply notice is tied to the current recording — it must vanish
        // the moment that recording ends, not linger into the next cycle.
        let appState = AppState()
        appState.apply(.recording)
        appState.apply(notice: "Activation key changed to Left Control. Press it to stop the current recording.")
        #expect(appState.notice != nil)
        appState.apply(.processing)
        #expect(appState.notice == nil)
    }

    @MainActor
    @Test("bind(to:) wires state, notices, and errors from a real session end to end")
    func bindWiresAllThreeChannels() async throws {
        // `apply(_:)` is unit-tested above, but nothing asserts `bind` actually
        // connects the three publishers. A dropped `.sink` or a mis-wired
        // publisher would pass every `apply` test while the menu silently stops
        // updating. Drive a real `FreeFlowSession` cycle and assert all three
        // observable properties track — including the notice's clear-on-end.
        let env = makeBoundEnv()
        try await env.session.start()
        env.store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // activeMode → tap

        env.session.handleActivate()                       // → .recording (state channel)
        #expect(env.appState.state == .recording)

        env.store.setValue(59, for: Settings.activationKeyCode)  // live tap-mode change → notice channel
        #expect(env.appState.notice != nil)

        await env.session.handleDeactivate()               // no buffer → .audioCapture (error channel)
        #expect(env.appState.state == .idle)               // state tracked through the whole cycle
        #expect(env.appState.errorMessage != nil)          // the cycle error reached the observable
        #expect(env.appState.notice == nil)                // notice cleared when the recording ended
    }

    // MARK: - Test environment

    @MainActor
    private struct BoundEnv {
        let appState: AppState
        let session: FreeFlowSession
        let store: SettingsStore
    }

    // A real session (fakes only at the untestable OS-call leaves — the mic
    // engine is skipped) bound to a real AppState, so the test exercises the
    // actual `bind` subscriptions rather than calling `apply` directly.
    @MainActor
    private func makeBoundEnv() -> BoundEnv {
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
            transcription: TranscriptionManager(),
            settings: store
        )
        let appState = AppState()
        appState.bind(to: session)
        return BoundEnv(appState: appState, session: session, store: store)
    }
}
