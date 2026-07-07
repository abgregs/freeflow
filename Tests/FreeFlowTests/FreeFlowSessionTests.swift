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
        // Two disruptive settings (key + mode) each emit their current value on
        // subscribe and apply while idle.
        #expect(env.session.configurationApplyCount == 2)
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
    @Test("activation mode change while idle applies immediately")
    func modeChangeWhileIdleApplies() async throws {
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount
        env.store.setValue(ActivationMode.doubleTap, for: Settings.activationMode)
        #expect(env.session.configurationApplyCount == baseline + 1)
        #expect(env.session.configurationDeferCount == 0)
    }

    @MainActor
    @Test("a tap-mode key change while recording applies live, keeps recording, and notifies")
    func tapModeKeyChangeAppliesLive() async throws {
        // The user changed the hotkey mid-recording in a tap mode. Unlike Hold
        // (which defers), this applies immediately — the recording continues and a
        // notice tells the user the new key now stops it. See free-flow-session.md.
        let env = makeSession()
        try await env.session.start()
        env.store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // activeMode → singleTap

        var notices: [String] = []
        let token = env.session.notices.sink { notices.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()  // → .recording
        #expect(env.session.currentState == .recording)
        let baseline = env.session.configurationApplyCount

        env.store.setValue(59, for: Settings.activationKeyCode)  // change key mid-recording

        #expect(env.session.currentState == .recording)              // not deferred, not stopped
        #expect(env.session.configurationApplyCount == baseline + 1)  // applied live
        #expect(env.session.configurationDeferCount == 0)
        #expect(notices.count == 1)
    }

    @MainActor
    @Test("start subscribes to the model publisher and applies the current selection while idle")
    func startSubscribesToModel() async throws {
        // planning 0021: the selectedModel publisher emits its current value on
        // subscribe and applies while idle — a separate counter from the hotkey path.
        let env = makeSession()
        #expect(env.session.modelReloadApplyCount == 0)
        try await env.session.start()
        #expect(env.session.modelReloadApplyCount == 1)
        #expect(env.session.modelReloadDeferCount == 0)
        #expect(env.session.configurationApplyCount == 2)  // hotkey path unaffected
    }

    @MainActor
    @Test("model change while idle applies immediately")
    func modelChangeWhileIdleApplies() async throws {
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.modelReloadApplyCount
        env.store.setValue("openai_whisper-base.en", for: Settings.selectedModel)
        #expect(env.session.modelReloadApplyCount == baseline + 1)
        #expect(env.session.modelReloadDeferCount == 0)
        // The switch is applied through a MainActor Task, so the re-point lands on the
        // next turn of the run loop, not synchronously.
        await waitUntil { env.transcription.currentModelName == "openai_whisper-base.en" }
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
    }

    @MainActor
    @Test("a model change mid-cycle defers to the return to .idle")
    func modelChangeMidCycleDefers() async throws {
        // A switch mid-recording/processing must never reload the model out from
        // under the in-flight transcribe; it parks and applies on return to .idle
        // (planning 0021 AC2), mirroring the hotkey deferral.
        let env = makeSession()
        try await env.session.start()
        let applyBaseline = env.session.modelReloadApplyCount

        env.session.handleActivate()  // → .recording (Hold default)
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue("openai_whisper-base.en", for: Settings.selectedModel)
        #expect(env.session.modelReloadApplyCount == applyBaseline)   // not applied yet
        #expect(env.session.modelReloadDeferCount == 1)               // parked
        #expect(env.transcription.currentModelName == Constants.defaultModel)  // still the old model

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.session.modelReloadApplyCount == applyBaseline + 1)        // pending applied
        await waitUntil { env.transcription.currentModelName == "openai_whisper-base.en" }
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
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
    @Test("an all-silence recording completes the cycle with no error emitted")
    func allSilenceRecordingEmitsNoError() async throws {
        // A stray key-brush captures pure silence. `makeBuffer()` is zeros, which
        // stopRecording's silence trim reduces to empty; the session must skip
        // decode/paste and NOT raise the error glyph — silence is not a failure.
        // The `.recording → .processing → .idle` cycle must still complete cleanly
        // (planning 0023 AC2). Contrast with the no-buffer path, which throws
        // .noAudioCaptured and DOES surface an error.
        let env = makeSession()
        var errors: [FreeFlowError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())  // silent zeros → trims to empty
        await env.session.handleDeactivate()

        #expect(env.session.currentState == .idle)
        #expect(errors.isEmpty)
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
    @Test("two settings deferred during one Hold recording both apply on return to .idle")
    func multipleDeferredReconfigurationsAllApply() async throws {
        // A single pending slot would drop the earlier change. With activeMode ==
        // .hold (the default), both a key and a mode change during the recording
        // defer, and both must land when the cycle returns to .idle.
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue(59, for: Settings.activationKeyCode)                     // deferred
        env.store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // deferred
        #expect(env.session.configurationApplyCount == baseline)   // both parked, none lost
        #expect(env.session.configurationDeferCount == 2)

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.session.configurationApplyCount == baseline + 2)  // both applied
    }

    @MainActor
    @Test(.disabled("end-to-end paste verification requires a loaded WhisperKit model + Accessibility grant — manual on-device before release. The insertion-catch branch in handleDeactivate is structurally identical to the transcription-catch (which is already covered by handleDeactivateReturnsToIdleOnAudioError indirectly) — reaching it in a unit test would require injecting a success-path TranscriptionManager fake, which ADR 0001 defers until a second adapter shows up."))
    func endToEndPasteCycle() async throws {
        // Placeholder lives here so the gap is locatable in the suite, not
        // hidden in a doc. If this comment grows to a third bullet, the ADR
        // revisit trigger has fired — extract a TranscriptionManager protocol.
    }

    @MainActor
    @Test("cancel from .recording returns to .idle with no error and a canceled notice")
    func cancelFromRecordingReturnsToIdle() async throws {
        // Planning 0017 AC1: the discard transition ends the recording with NO
        // transcription and NO paste (structural — handleCancel never calls either),
        // no error on the cycle-failure channel, and a visible "canceled" notice.
        let env = makeSession()
        try await env.session.start()

        var errors: [FreeFlowError] = []
        var notices: [String] = []
        let errToken = env.session.errors.sink { errors.append($0) }
        let noticeToken = env.session.notices.sink { notices.append($0) }
        defer { errToken.cancel(); noticeToken.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)  // let startRecording subscribe
        #expect(env.session.currentState == .recording)

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(errors.isEmpty)                                      // no cycle error
        #expect(notices == [ActivationNotice.recordingCanceled])    // visible, not silent
    }

    @MainActor
    @Test("cancel while .idle is a no-op")
    func cancelWhileIdleIsNoOp() async throws {
        // Planning 0017 AC2: cancel outside .recording changes nothing and emits
        // no notice (logged only).
        let env = makeSession()
        try await env.session.start()
        var notices: [String] = []
        let token = env.session.notices.sink { notices.append($0) }
        defer { token.cancel() }

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(notices.isEmpty)
    }

    @MainActor
    @Test("cancel while .processing is a no-op (out of scope)")
    func cancelWhileProcessingIsNoOp() async throws {
        // Planning 0017: cancel during .processing is ignored — transcription is
        // already in flight and the paste is imminent. Drive into .processing by
        // starting handleDeactivate with no buffer (it sits in the ~300 ms warmup
        // wait), cancel during that window, and confirm the state is unaffected.
        let env = makeSession()
        try await env.session.start()
        var notices: [String] = []
        let token = env.session.notices.sink { notices.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        let deactivate = Task { @MainActor in await env.session.handleDeactivate() }
        try await Task.sleep(nanoseconds: 20_000_000)  // now in .processing, mid-warmup-wait
        #expect(env.session.currentState == .processing)

        env.session.handleCancel()
        #expect(env.session.currentState == .processing)  // unaffected
        #expect(notices.isEmpty)

        await deactivate.value                              // let the cycle finish
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("a settings change deferred during a canceled recording still applies on return to .idle")
    func pendingReconfigurationAppliesOnCancel() async throws {
        // Planning 0017 AC3: the cancel path runs the same deferral loop as the
        // normal cycle end. A key change parked during the (Hold-mode) recording
        // must land when cancel returns the session to .idle — cancel is not a
        // shortcut that skips the deferral contract.
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue(59, for: Settings.activationKeyCode)  // deferred (Hold recording)
        #expect(env.session.configurationApplyCount == baseline)  // parked, not applied
        #expect(env.session.configurationDeferCount == 1)

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(env.session.configurationApplyCount == baseline + 1)  // pending applied on cancel
    }

    @MainActor
    @Test("a model switch deferred during a canceled recording still applies on return to .idle")
    func pendingModelSwitchAppliesOnCancel() async throws {
        // The model-switch deferral (planning 0021) shares the cancel return-to-idle
        // path: a switch parked mid-recording applies when cancel ends the cycle.
        let env = makeSession()
        try await env.session.start()
        let applyBaseline = env.session.modelReloadApplyCount

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue("openai_whisper-base.en", for: Settings.selectedModel)
        #expect(env.session.modelReloadApplyCount == applyBaseline)  // parked
        #expect(env.session.modelReloadDeferCount == 1)

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(env.session.modelReloadApplyCount == applyBaseline + 1)  // applied on cancel
        await waitUntil { env.transcription.currentModelName == "openai_whisper-base.en" }
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
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

    @MainActor
    @Test("handleActivate declines and emits a transcription error when the model is not yet ready")
    func handleActivateDeclinesWhenModelNotReady() {
        // Planning 0004 AC3: dictating before "Ready" must surface clear feedback
        // (via the error channel) and must NOT start a recording that loses audio.
        let env = makeSession()
        env.transcription.setModelLoadStateForTesting(.loading)  // not ready

        var errors: [FreeFlowError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()

        #expect(env.session.currentState == .idle)   // never entered .recording
        #expect(errors.count == 1)
        guard case .transcription = errors.first else {
            Issue.record("expected .transcription, got \(String(describing: errors.first))")
            return
        }
    }

    @MainActor
    @Test("handleActivate declines during download phase")
    func handleActivateDeclinesWhenDownloading() {
        let env = makeSession()
        env.transcription.setModelLoadStateForTesting(.downloading)

        env.session.handleActivate()
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
        let transcription: TranscriptionManager
    }

    @MainActor
    private func makeSession() -> TestEnv {
        let accessibility = AccessibilityCapability()
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let inputMonitoring = InputMonitoringCapability()
        let hotkey = HotkeyManager(inputMonitoring: inputMonitoring, initialKeyCode: 62)
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let transcription = TranscriptionManager()
        // Unit tests never load the real model, so mark the model as ready to
        // exercise the normal recording path without triggering the model gate, and
        // skip the async reload so a model switch (planning 0021) exercises the
        // session's apply-or-defer routing without a real WhisperKit download.
        transcription.setModelLoadStateForTesting(.ready)
        transcription.skipLoadForTesting = true
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
        return TestEnv(
            session: session,
            store: store,
            hotkey: hotkey,
            inputMonitoring: inputMonitoring,
            microphone: microphone,
            transcription: transcription
        )
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)   // up to ~1s total
        }
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
