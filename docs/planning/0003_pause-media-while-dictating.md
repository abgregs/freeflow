# Planning: Pause Media While Dictating (roadmap 0003)

A queued roadmap item, deferred out of M8. Pauses now-playing media (Music, Spotify, a browser video) when a recording starts and resumes it when the cycle ends, so dictation isn't fighting background audio.

> **Status (2026-09-14): PR #34 closed unmerged; spec retained for a rework.** On macOS 15.4+ the private `MediaRemote` now-playing query is blocked for third-party apps (a YouTube tab kept playing in the on-device smoke), so the idempotency guard below has no reliable input. The implementation also had a pause/resume race and no timeout on the now-playing callback. Its commit was reverted out of the Sparkle PR (#35) before that merged; the branch `feat/0003-pause-media-while-dictating` is kept as the rework source.

## Problem

Recording over playing audio is both annoying (the user hears their music while talking) and slightly worse for capture. The setting `pauseMediaWhileDictating` (default `true`) and its consumer `MediaPauseManager` are named in [../architecture/configuration.md](../architecture/configuration.md), but neither exists yet. M8 deliberately shipped the rest of Settings **without** this toggle rather than ship an inert control — see [current-focus.md](current-focus.md) and the no-silent-no-op rule in [../conventions/anti-patterns.md](../conventions/anti-patterns.md).

## Mechanism (to decide during implementation)

The hard part is doing this **idempotently** — pause on record-start, resume on record-end, but never *start* media that was already paused.

- **Now-playing state** must be read first (only pause if something is actually playing; only resume what we paused). The candidate API is the private `MediaRemote` framework (`MRMediaRemoteGetNowPlayingApplicationIsPlaying`). Private API — acceptable for this app's distribution (not App Store; see [../architecture/distribution.md](../architecture/distribution.md)) but a notarization/longevity risk to weigh.
- **Pause/resume** via a synthesized `NX_KEYTYPE_PLAY` system-defined media key, or `MRMediaRemoteSendCommand`. The media key is a *toggle*, which is exactly why the now-playing read is load-bearing.

`MediaPauseManager` owns whichever APIs are chosen (mirrors the capability "one owner per OS surface" shape). `RiverSession` calls `pauseIfPlaying()` on entry to `.recording` and `resumeIfPaused()` on the return to `.idle`, gated by the setting — but only resumes what it paused (track that state in the manager).

Because the candidate API is private, it can break under an OS update. If it does, the manager must **degrade loudly** — log the failure and surface that the feature is inoperative (or disable the toggle) — never leave a live toggle silently doing nothing, per the no-silent-no-op rule the deferral itself was about.

## Acceptance criteria

1. Toggle on + media playing → recording pauses it; cycle end resumes it.
2. Toggle on + media already paused → nothing is resumed afterward (no spurious playback).
3. Toggle off → media is never touched.
4. The now-playing read and the pause/resume decision are unit-tested behind an injectable seam; the OS-call leaf is isolated (mirrors `AccessibilityCapability.probe()`).

## Related

- [../architecture/configuration.md](../architecture/configuration.md) — declares `pauseMediaWhileDictating` → `MediaPauseManager`
- [../architecture/river-pipeline.md](../architecture/river-pipeline.md) — the cycle that would call pause/resume at `.recording` / `.idle`
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — why the toggle wasn't shipped inert in M8
