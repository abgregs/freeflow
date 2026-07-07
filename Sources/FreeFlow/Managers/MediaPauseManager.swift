import Darwin
import Foundation
import os

// Testable seam — lets tests replace the real OS calls with a recording fake.
// All MediaRemote API access routes through this protocol (single OS surface,
// AGENTS.md rule #3).
protocol MediaControlling: AnyObject {
    func isPlaying() async -> Bool
    func sendPause()
    func sendPlay()
}

// Live implementation: loads the private MediaRemote framework via dlopen/dlsym
// because there is no stable Swift import. All three symbol loads are isolated
// here — the single OS-call site for this feature (AGENTS.md rule #3).
//
// Degrades loudly if the framework or either symbol is missing (e.g. a future
// OS update renames or removes it): logs at .error, returns false / no-ops for
// sendPause and sendPlay, so the toggle becomes a confirmed no-op rather than a
// silent lie (spec: "degrade loudly"; anti-pattern #5).
final class LiveMediaController: MediaControlling {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "media")

    // C-convention typealiases matching the private MediaRemote signatures.
    // The queue/block pair maps to DispatchQueue + closure; the @convention(c)
    // wrapping treats the Swift closure as an Obj-C block at the call boundary.
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SendCommandFn  = @convention(c) (UInt32, AnyObject?) -> Bool

    // Pause=1, Play=0 — the stable MediaRemote command codes.
    private enum MRCommand: UInt32 { case play = 0, pause = 1 }

    private let getIsPlayingFn: GetIsPlayingFn?
    private let sendCommandFn: SendCommandFn?

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            Logger(subsystem: Constants.loggingSubsystem, category: "media")
                .error("MediaRemote: framework not found — pauseMediaWhileDictating is inoperative")
            getIsPlayingFn = nil
            sendCommandFn = nil
            return
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlayingFn = unsafeBitCast(sym, to: GetIsPlayingFn.self)
        } else {
            Logger(subsystem: Constants.loggingSubsystem, category: "media")
                .error("MediaRemote: MRMediaRemoteGetNowPlayingApplicationIsPlaying not found — inoperative")
            getIsPlayingFn = nil
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFn = unsafeBitCast(sym, to: SendCommandFn.self)
        } else {
            Logger(subsystem: Constants.loggingSubsystem, category: "media")
                .error("MediaRemote: MRMediaRemoteSendCommand not found — inoperative")
            sendCommandFn = nil
        }
    }

    func isPlaying() async -> Bool {
        guard let fn = getIsPlayingFn else { return false }
        return await withCheckedContinuation { continuation in
            fn(.main) { playing in continuation.resume(returning: playing) }
        }
    }

    func sendPause() {
        guard let fn = sendCommandFn else { return }
        _ = fn(MRCommand.pause.rawValue, nil)
    }

    func sendPlay() {
        guard let fn = sendCommandFn else { return }
        _ = fn(MRCommand.play.rawValue, nil)
    }
}

// Owns the pause/resume decision for the media feature (planning 0003).
// FreeFlowSession calls pauseIfPlaying() on entering .recording (when the
// setting is on) and resumeIfPaused() on every return to .idle — deactivate,
// cancel, and all-silence paths all go through the same resume.
//
// Only resumes what IT paused: if nothing was playing at pause time, the
// manager's didPause flag stays false and resumeIfPaused is a no-op (AC2).
@MainActor
final class MediaPauseManager {
    private let controller: any MediaControlling
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "media")

    // Set inside the pauseIfPlaying Task after isPlaying() returns true.
    // Read synchronously by resumeIfPaused — the only gate for spurious-resume
    // prevention.
    private var didPause = false

    init(controller: (any MediaControlling)? = nil) {
        self.controller = controller ?? LiveMediaController()
    }

    // Called on entry to .recording when the setting is on. Reads the
    // now-playing state (async MediaRemote callback) and pauses if playing.
    //
    // Fire-and-forget: the begin sound cue is also async (via AppState
    // observation), so both race naturally. In practice the cue plays first
    // (NSSound is synchronous once scheduled) and the media pauses a few
    // milliseconds later via the MediaRemote callback — acceptable and the
    // simpler posture per the spec.
    //
    // internal for testability — tests call it on a FakeMediaController and
    // await a Task.sleep to let the inner Task complete before asserting.
    func pauseIfPlaying() {
        Task { @MainActor in
            let playing = await self.controller.isPlaying()
            guard playing else {
                self.logger.info("MediaPauseManager: media not playing, nothing to pause")
                return
            }
            self.controller.sendPause()
            self.didPause = true
            self.logger.info("MediaPauseManager: paused media for dictation")
        }
    }

    // Called on every return to .idle. No-op if this manager did not pause
    // (AC2: never starts media that was already stopped before dictation).
    //
    // internal for testability — tests assert resumeIfPaused is a no-op when
    // pauseIfPlaying found nothing playing.
    func resumeIfPaused() {
        guard didPause else { return }
        didPause = false
        controller.sendPlay()
        logger.info("MediaPauseManager: resumed media after dictation")
    }
}
