# Planning: Streaming Dictation (roadmap 0025)

A queued backlog item, planned 2026-07-11. Deliver text incrementally *during* a long dictation instead of one paste at the end: while the user keeps talking, opportunistically cut the audio captured so far into a segment, transcribe it, and inject its text at the cursor — repeating until the user ends the dictation as usual (key release / tap). [0011](0011_keystroke-injection.md)'s keystroke injection was explicitly built as the foundation for this ("append-only streaming dictation"); this spec is that feature.

## Problem

Today the cycle is strictly one-shot: the entire recording is harvested at deactivate, transcribed once, pasted once. For long dictations the user stares at a silent cursor for the full recording *plus* the full transcription, and the perceived latency grows with dictation length. Natural pauses in speech are moments where partial text could already be landing.

## The load-bearing insight: no second recording, no gap

The naive design — stop the recording, transcribe it, quickly start a new one — has an audio-loss seam (engine teardown + the warmup race) exactly where the user fears it. The architecture already offers the safe version: `MicrophoneCapability`'s tap continuously publishes buffers and `AudioCaptureManager` accumulates them in an in-memory array. A segment cut is a **drain of that array while the engine keeps running** — the tap never stops, so a mid-dictation audio gap is impossible *by construction*, the same style of guarantee as 0011's clipboard-race elimination.

## Design

1. **`drainSegment()` on `AudioCaptureManager`** — a third harvest operation beside `stopRecording()` and 0017's `discardRecording()`: snapshot the accumulated buffers, clear the array, run the existing `convert` + 0023 trim, return the samples. Engine, tap, and subscription untouched. No warmup wait (a mid-stream drain already has buffers).
2. **Cut criteria — silence first, timer as fallback; all `Constants` tunables, no settings** (the `doubleTapWindowMs` precedent). Cut when *(sustained silence ≥ a threshold, on the order of ~0.7–1.0 s)* **and** *(the segment holds ≥ a minimum of speech, ~1–2 s)* — hysteresis, so inter-word gaps don't produce confetti segments. If no natural pause arrives, a max-segment-duration fallback (~20–30 s) forces a cut **at the lowest-energy window in the recent audio**, never at an arbitrary instant: a mid-word cut garbles both halves in Whisper, so boundary placement is a transcription-*accuracy* requirement, not just polish. The detector consumes the same per-buffer RMS that [0020](0020_mic-level-meter.md) computes in `MicrophoneCapability` and compares against thresholds shared with [0023](0023_silence-decoding-hardening.md)'s trim helper — one energy vocabulary, no duplicate math.
3. **A serialized segment pipeline: FIFO transcribe → insert.** `TranscriptionManager` has no reentrancy guard and WhisperKit's concurrency safety is unverified — segments are transcribed **one at a time, in order**, and pastes are strictly ordered (an out-of-order paste scrambles the user's text; worse than any latency). If speech outpaces the model, segments queue; the queue drains in order. This is also ADR 0001's deferred-protocol trigger: the pipeline needs a `TranscriptionManager` seam for testing, and "a second adapter showed up" is now true.
4. **State machine: stay `.recording` for the whole session.** Segment transcription runs as background work while the state remains `.recording`; `.processing` means exactly what it means today — capture is over, the final flush is in flight. **Never bounce through `.idle` mid-session**: `.idle` is what fires deferred reconfigurations, media resume ([0003](0003_pause-media-while-dictating.md)), and sound-cue boundaries ([0016](0016_recording-sound-cues.md)) — all of which must span the full dictation. Segment lifecycle events travel on a side channel (a new session publisher), not on `FreeFlowState`. The per-session state sequence stays `[.idle, .recording, .processing, .idle]`.
5. **End of session: the final flush.** On deactivate, the remaining buffer is drained as the last segment, the engine stops, the state moves to `.processing`, the pipeline drains any queued segments plus the final one in order, and the session returns to `.idle`. Deferred reconfigurations and the 0021 model switch apply there — "next `.idle`" always means session end.
6. **Per-segment decode hygiene comes from 0023.** Each segment decodes under the same `noSpeechThreshold`/log-prob/temperature-fallback gates; a segment that trims to empty (the user paused, the cut fired, nothing voiced) pastes nothing, raises nothing, and the session keeps recording — the streaming analogue of 0023's quiet no-op.
7. **Per-segment insertion re-runs the [0001](0001_focused-element-paste-guard.md) guard.** Each segment's insert independently classifies the focused target — correct behavior if the user clicks away mid-dictation (later segments skip with the existing notice; already-inserted text stays).
8. **No cross-segment prompt conditioning in v1.** Feeding the previous segment's text as `promptTokens` is the standard continuity technique, but it is exactly the mechanism behind the [0008](0008_custom-dictionary-redesign.md) prompt-echo field bug. v1 decodes each segment cold; punctuation/casing continuity across cuts is an accepted limitation, re-evaluated later with [0022](0022_transcription-eval-harness.md) evidence before any conditioning is added.
9. **Ships as a setting; one-shot remains the default.** One `Settings.streamingDictation` `Bool` key (user-facing behavior → `SettingsStore` from day 1, load-bearing rule #5). Off = the current one-shot path, byte-identical. The default flips only after on-device experience earns it.
10. **Mid-session errors get a surface.** Today `errorSubject` is only fed at deactivate; a failed segment mid-`.recording` must emit through the same publisher (rendered by the [0018](0018_transient-error-toasts.md) toast layer, whose auto-clear rule must not treat the *ongoing* recording as "a fresh recording" that suppresses the toast). A single failed segment does not end the session.

## Amendments to queued specs (semantics change under streaming)

- **[0017](0017_cancel-recording.md) cancel = discard the un-pasted tail.** The one-shot promise "no transcription, no paste" cannot hold once segments have already landed. Under streaming, cancel discards the un-drained buffer *and* the queued/in-flight un-pasted segments; **already-inserted text stays** — no undo, no synthesized delete keystrokes (fragile across apps, and rewriting the user's document is a worse failure class). Notice copy must be honest about this ("Recording canceled — text already inserted stays").
- **[0019](0019_last-transcript-recovery.md) "last transcript" = the accumulated session, not the last segment.** The retained transcript is the concatenation of every segment inserted (or attempted) this session, built up by the segment pipeline; recovering a two-word final segment from a ten-segment dictation is useless. Memory-only/never-logged holds unchanged; the write moves from the single deactivate site into the pipeline.

## Interactions with queued work (no rework required)

- **[0020](0020_mic-level-meter.md)** supplies the live RMS signal the cut detector consumes; because the state stays `.recording`, the HUD meter keeps running through segment transcription for free (the meter zeroes on `.processing`, which now only happens at the true end).
- **[0023](0023_silence-decoding-hardening.md)** supplies the energy thresholds, the trim helper (needing a rolling-window variant for mid-capture detection), and the per-segment decode gates. Its mid-session analogue inverts one rule: inter-segment silence is *expected* (it's the cut cue), never a "you didn't say anything" notice — that notice applies only to an all-silence *session*.
- **[0022](0022_transcription-eval-harness.md)** is the go/no-go instrument: the per-clip latency scorecard answers "does this model transcribe an N-second segment in well under N seconds on this hardware," and short-segment fixtures measure the accuracy cost of cold cuts.
- **[0004](0004_model-loading-indicator.md)** — the synchronous `.ready` check gates activation as designed; the pipeline additionally checks it per segment (cheap, `CurrentValueSubject`).
- **[0016](0016_recording-sound-cues.md)** — cues stay bound to the true session boundaries (state transitions), which the stay-`.recording` decision preserves; per-segment cues are ruled out (they'd bleed into live capture).
- **[0002](0002_recording-indicator-hud.md)/[0018](0018_transient-error-toasts.md)** — the HUD gains an optional segment-activity affordance later, driven by the side channel, not by new `FreeFlowState` cases.

## Accepted limitations (on record)

- **Streaming commits early.** One-shot output can never contradict itself; a pasted segment can't be revised by a later one. Whisper also loses cross-cut context (see design #8). Users who prefer maximal accuracy keep the one-shot mode — that's why it's a setting.
- **The cursor is wherever the user left it.** Segments paste at the live cursor; moving it mid-dictation interleaves text at the new position. Per-segment guarding (design #7) handles non-editable targets, not repositioning.

## Acceptance criteria

1. `drainSegment()` never touches the engine/tap/subscription: a session-level test drains mid-recording and shows subsequent buffers still accumulate (no-gap-by-construction pinned).
2. Segments transcribe serially and paste in dictation order — a test with delayed fake transcriptions proves an earlier slow segment still pastes before a later fast one.
3. The per-session state sequence is unchanged (`[.idle, .recording, .processing, .idle]`); the existing sequence test passes as-is; deferred reconfigurations and the 0021 model switch apply only at session end.
4. A segment trimming to empty pastes nothing, surfaces nothing, and the session continues; a failed segment emits on `errors` without ending the session.
5. With `Settings.streamingDictation` off, behavior is byte-identical to one-shot (existing suite green untouched).
6. Cancel mid-stream discards only un-pasted work; the 0019 recovered transcript equals the full concatenation of inserted text.
7. All cut tunables (silence duration, min speech, max segment, energy threshold) live in `Constants`; exactly one new `SettingKey`.
8. On-device gate: a multi-paragraph dictation with natural pauses lands text incrementally with no dropped or duplicated words at any boundary, verified across the 0021 curated model list.

## Related

- [0011_keystroke-injection.md](0011_keystroke-injection.md) — the append-only insertion foundation this was anticipated by
- [0023_silence-decoding-hardening.md](0023_silence-decoding-hardening.md) / [0020_mic-level-meter.md](0020_mic-level-meter.md) — the energy/RMS building blocks the cut detector reuses
- [0022_transcription-eval-harness.md](0022_transcription-eval-harness.md) — the latency/accuracy instrument that decides streaming viability per model
- [0017_cancel-recording.md](0017_cancel-recording.md) / [0019_last-transcript-recovery.md](0019_last-transcript-recovery.md) — semantics amended above
- [../architecture/free-flow-session.md](../architecture/free-flow-session.md) / [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — the cycle and state machine this extends
- [../decisions/0001-defer-cycle-protocol-seams.md](../decisions/0001-defer-cycle-protocol-seams.md) — the deferred `TranscriptionManager` protocol whose extraction trigger this fires
