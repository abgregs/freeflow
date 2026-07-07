import Foundation
import Testing
@testable import FreeFlow

// Shared fake — also consumed by FreeFlowSessionTests to populate makeSession().
@MainActor
final class FakeMediaController: MediaControlling {
    // Controls what isPlaying() returns. Tests set this before calling pauseIfPlaying().
    var playingStub = false
    private(set) var pauseCount = 0
    private(set) var playCount = 0

    func isPlaying() async -> Bool { playingStub }
    func sendPause() { pauseCount += 1 }
    func sendPlay() { playCount += 1 }
}

@MainActor
@Suite("MediaPauseManager")
struct MediaPauseManagerTests {

    // MARK: - AC1: pause when playing, resume after

    @Test("pauseIfPlaying with media playing pauses and sets didPause")
    func pauseIfPlayingWhenPlayingPauses() async throws {
        let (manager, fake) = makeManager()
        fake.playingStub = true

        manager.pauseIfPlaying()
        // Let the inner Task (async isPlaying callback) run.
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(fake.pauseCount == 1)
    }

    @Test("resumeIfPaused after a pause sends play")
    func resumeIfPausedAfterPauseSendsPlay() async throws {
        let (manager, fake) = makeManager()
        fake.playingStub = true

        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)  // let pause task complete

        manager.resumeIfPaused()

        #expect(fake.playCount == 1)
    }

    @Test("resumeIfPaused is idempotent: only resumes once")
    func resumeIfPausedIsIdempotent() async throws {
        let (manager, fake) = makeManager()
        fake.playingStub = true

        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)

        manager.resumeIfPaused()
        manager.resumeIfPaused()  // second call should no-op

        #expect(fake.playCount == 1)
    }

    // MARK: - AC2: no spurious resume when nothing was playing

    @Test("pauseIfPlaying with media not playing does not pause")
    func pauseIfPlayingWhenNotPlayingDoesNotPause() async throws {
        let (manager, fake) = makeManager()
        fake.playingStub = false  // explicit: nothing playing

        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(fake.pauseCount == 0)
    }

    @Test("resumeIfPaused after no pause does not send play (AC2 no spurious resume)")
    func resumeIfPausedWithoutPriorPauseIsNoOp() async throws {
        let (manager, fake) = makeManager()
        fake.playingStub = false

        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)

        manager.resumeIfPaused()  // nothing was paused, must not start playback

        #expect(fake.pauseCount == 0)
        #expect(fake.playCount == 0)
    }

    @Test("resumeIfPaused without any pauseIfPlaying call is a no-op")
    func resumeWithoutPauseIsNoOp() {
        let (manager, fake) = makeManager()
        manager.resumeIfPaused()
        #expect(fake.playCount == 0)
    }

    // MARK: - Multiple cycles

    @Test("second cycle correctly pauses and resumes after the first completes")
    func secondCyclePausesAndResumes() async throws {
        let (manager, fake) = makeManager()
        fake.playingStub = true

        // First cycle.
        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)
        manager.resumeIfPaused()

        // Second cycle.
        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)
        manager.resumeIfPaused()

        #expect(fake.pauseCount == 2)
        #expect(fake.playCount == 2)
    }

    @Test("second cycle: not playing means no resume even after a played first cycle")
    func secondCycleNotPlayingNoResume() async throws {
        let (manager, fake) = makeManager()

        // First cycle — playing.
        fake.playingStub = true
        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)
        manager.resumeIfPaused()

        // Second cycle — media already stopped by the user.
        fake.playingStub = false
        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)
        manager.resumeIfPaused()

        #expect(fake.pauseCount == 1)   // only the first cycle
        #expect(fake.playCount == 1)    // only the first cycle
    }

    // MARK: - Cancel path

    @Test("cancel path: resumeIfPaused after a playing-then-cancel cycle still resumes")
    func cancelPathResumesMedia() async throws {
        // AGENTS.md / 0017: a canceled recording must also resume paused media.
        let (manager, fake) = makeManager()
        fake.playingStub = true

        manager.pauseIfPlaying()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Simulate cancel: session calls resumeIfPaused on the cancel path too.
        manager.resumeIfPaused()

        #expect(fake.pauseCount == 1)
        #expect(fake.playCount == 1)
    }

    // MARK: - Helpers

    private func makeManager() -> (MediaPauseManager, FakeMediaController) {
        let fake = FakeMediaController()
        let manager = MediaPauseManager(controller: fake)
        return (manager, fake)
    }
}
