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

    @Test("recording→idle produces no cue")
    func recordingToIdleIsNil() {
        #expect(SoundFeedbackController.cue(from: .recording, to: .idle) == nil)
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
