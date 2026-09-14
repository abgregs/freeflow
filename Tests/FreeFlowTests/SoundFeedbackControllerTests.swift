import Foundation
import Testing
@testable import FreeFlow

@MainActor
@Suite("SoundFeedbackController")
struct SoundFeedbackControllerTests {

    // MARK: - Pure cue mapping

    @Test("idle→recording produces begin cue")
    func idleToRecordingIsBegin() {
        #expect(SoundFeedbackController.cue(from: .idle, to: .recording) == .begin)
    }

    @Test("recording→processing produces end cue")
    func recordingToProcessingIsEnd() {
        #expect(SoundFeedbackController.cue(from: .recording, to: .processing) == .end)
    }

    @Test("processing→idle produces no cue")
    func processingToIdleIsNil() {
        #expect(SoundFeedbackController.cue(from: .processing, to: .idle) == nil)
    }

    @Test("idle→processing produces no cue")
    func idleToProcessingIsNil() {
        #expect(SoundFeedbackController.cue(from: .idle, to: .processing) == nil)
    }

    @Test("recording→idle (a canceled recording) produces the cancel cue")
    func recordingToIdleIsCancel() {
        // Planning 0017: cancel transitions .recording → .idle directly, and gets
        // its own cue — not the end cue (which means "now transcribing," and a
        // discard is not that), and not silence (0016 exists for the moment the
        // user is looking at the text field rather than the HUD).
        #expect(SoundFeedbackController.cue(from: .recording, to: .idle) == .cancel)
    }

    @Test("the cancel cue is distinct from the begin and end cues")
    func cancelCueIsDistinct() {
        // The point of a third cue is that it is tellable apart. If a future
        // refactor collapses cancel onto begin or end, this fails.
        let cancel = SoundFeedbackController.cue(from: .recording, to: .idle)
        #expect(cancel != SoundFeedbackController.cue(from: .idle, to: .recording))
        #expect(cancel != SoundFeedbackController.cue(from: .recording, to: .processing))
    }

    // MARK: - handleStateChange with setting on

    @Test("begin cue plays when toggle is on and recording starts")
    func beginCuePlaysWhenEnabled() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin])
    }

    @Test("end cue plays when toggle is on and recording stops")
    func endCuePlaysWhenEnabled() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin, .end])
    }

    // MARK: - handleStateChange with setting off

    @Test("no cue plays when toggle is off")
    func noCuePlaysWhenDisabled() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: false)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues.isEmpty)
    }

    // MARK: - Multiple cycles

    @Test("begin and end cues play for each successive cycle when toggle is on")
    func cuePlaysForMultipleCycles() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()
        appState.apply(.idle)
        controller.handleStateChange()   // processing→idle: no cue

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin, .end, .begin, .end])
    }

    @Test("a canceled cycle cues begin then cancel, and the next cycle is unaffected")
    func canceledCycleThenNormalCycle() {
        // Exercises previousState bookkeeping across the cancel path: the canceled
        // cycle must not leave the controller mis-tracking state such that the
        // following normal cycle loses or duplicates a cue.
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.idle)            // canceled: recording→idle
        controller.handleStateChange()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin, .cancel, .begin, .end])
    }

    @Test("no cancel cue plays when the toggle is off")
    func cancelCueRespectsTheToggle() {
        // The third cue rides the same single setting — no separate switch.
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: false)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.idle)
        controller.handleStateChange()

        #expect(fakePlayer.cues.isEmpty)
    }

    // MARK: - Helpers

    private func makeController(
        soundsEnabled: Bool
    ) -> (SoundFeedbackController, FakeSoundFeedbackPlayer, AppState) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.setValue(soundsEnabled, for: Settings.playFeedbackSounds)
        let appState = AppState()
        let fakePlayer = FakeSoundFeedbackPlayer()
        let controller = SoundFeedbackController(appState: appState, settings: store, player: fakePlayer)
        return (controller, fakePlayer, appState)
    }
}

// MARK: - Fake player

@MainActor
final class FakeSoundFeedbackPlayer: SoundFeedbackPlaying {
    private(set) var cues: [SoundCue] = []
    func play(_ cue: SoundCue) { cues.append(cue) }
}
