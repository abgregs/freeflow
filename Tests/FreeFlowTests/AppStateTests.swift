import Combine
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

    @MainActor
    @Test("model load state propagates through apply(modelLoadState:)")
    func modelLoadStateApply() {
        // planning 0004: the load state entry point drives the menu bar's
        // download/load/ready label independently of the cycle state.
        let appState = AppState()
        #expect(appState.modelLoadState == .loading)  // default before bind
        appState.apply(modelLoadState: .downloading)
        #expect(appState.modelLoadState == .downloading)
        appState.apply(modelLoadState: .ready)
        #expect(appState.modelLoadState == .ready)
    }

    @MainActor
    @Test("bind(transcription:) wires model load state from the real publisher")
    func bindTranscriptionWiresModelLoadState() {
        let transcription = TranscriptionManager()
        let appState = AppState()
        appState.bind(transcription: transcription)

        // The bind subscribes to `modelLoadState` publisher via CurrentValueSubject,
        // which immediately delivers the current value on subscribe.
        let initialState = appState.modelLoadState
        // Should be .downloading or .loading depending on whether the model is
        // cached on this machine — either is valid, just not .ready or .failed.
        #expect(initialState == .downloading || initialState == .loading)

        // Driving via the test seam confirms the publisher → apply bridge is live.
        transcription.setModelLoadStateForTesting(.ready)
        #expect(appState.modelLoadState == .ready)
    }

    // MARK: - Error toast lifecycle (planning 0018)

    @MainActor
    @Test("a cycle error sets a transient toast alongside the lingering menu-row message")
    func errorSetsToast() {
        // Two renderers of one error (planning 0018): the redacted `errorMessage`
        // is the lingering menu record; the `toast` is the transient HUD alert.
        let appState = AppState()
        let error = FreeFlowError.textInsertion(underlying: NSError(domain: "x", code: 1))
        appState.apply(error)
        #expect(appState.toast == ErrorToastPresentation.toast(for: error))
        #expect(appState.errorMessage != nil)
    }

    @MainActor
    @Test("the toast auto-clears when its scheduled timer fires (injectable clock)")
    func toastAutoClearsOnTimer() {
        // AC1/AC4: the toast auto-dismisses after a bounded duration. An injected
        // scheduler fires the dismiss synchronously — no wall-clock wait — and
        // confirms the duration passed is the configured one.
        let scheduler = ManualToastScheduler()
        let appState = AppState(scheduleToastDismiss: scheduler.schedule)
        appState.apply(FreeFlowError.audioCapture(underlying: NSError(domain: "x", code: 1)))
        #expect(appState.toast != nil)
        #expect(scheduler.lastDelay == Constants.errorToastDurationSeconds)
        scheduler.fire()
        #expect(appState.toast == nil)
    }

    @MainActor
    @Test("a fresh recording clears a lingering toast (its timer is moot)")
    func recordingClearsToast() {
        let appState = AppState()
        appState.apply(FreeFlowError.transcription(underlying: NSError(domain: "x", code: 1)))
        #expect(appState.toast != nil)
        appState.apply(.recording)
        #expect(appState.toast == nil)
    }

    // MARK: - Input level (planning 0020)

    @MainActor
    @Test("input level is applied only during recording and resets when it ends")
    func inputLevelGatedByRecording() {
        // The meter is a *live-capture* signal. A level arriving while idle or
        // processing (a late buffer) must not raise the meter, and the meter must
        // sit at rest the moment the recording ends.
        let appState = AppState()
        appState.apply(inputLevel: 0.8)
        #expect(appState.inputLevel == 0)          // ignored while idle
        appState.apply(.recording)
        appState.apply(inputLevel: 0.8)
        #expect(appState.inputLevel == 0.8)        // tracked during recording
        appState.apply(.processing)
        #expect(appState.inputLevel == 0)          // reset when recording ends
    }

    @MainActor
    @Test("bind(microphone:) forwards the mic's level publisher into the observable")
    func bindMicrophoneWiresLevel() {
        // Nothing else asserts `bind(microphone:)` actually connects the publisher;
        // a dropped sink would pass every `apply(inputLevel:)` test while the HUD
        // meter silently stays dead. Drive a real emission through the subscription.
        let mic = MicrophoneCapability(now: { 0 })
        let appState = AppState()
        appState.apply(.recording)
        appState.bind(microphone: mic)
        mic.emitLevel(rms: Constants.levelMeterReferenceRMS)  // → normalized 1.0
        #expect(appState.inputLevel == 1.0)
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
        let transcription = TranscriptionManager()
        // Unit tests never load the real model — mark ready so handleActivate
        // exercises the recording path rather than the model-gate decline.
        transcription.setModelLoadStateForTesting(.ready)
        let session = FreeFlowSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: hotkey,
            audio: AudioCaptureManager(microphone: microphone),
            textInsertion: TextInsertionManager(accessibility: accessibility),
            transcription: transcription,
            settings: store
        )
        let appState = AppState()
        appState.bind(to: session)
        return BoundEnv(appState: appState, session: session, store: store)
    }
}

// Captures the scheduled toast-dismiss instead of dispatching it, so a test fires
// the auto-clear synchronously and asserts the delay — the injectable-clock pattern
// (planning 0018 AC4).
@MainActor
private final class ManualToastScheduler {
    private(set) var pending: (@MainActor () -> Void)?
    private(set) var lastDelay: TimeInterval?

    var schedule: ToastScheduler {
        { [weak self] delay, action in
            self?.lastDelay = delay
            self?.pending = action
            return AnyCancellable { self?.pending = nil }
        }
    }

    func fire() {
        let action = pending
        pending = nil
        action?()
    }
}
