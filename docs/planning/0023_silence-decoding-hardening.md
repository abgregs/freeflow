# Planning: Silence & Decoding Hardening (roadmap 0023)

A queued backlog item from the 2026-07-06 transcription-quality review. Eliminate the hallucinated-text-from-silence failure class: Whisper's best-known failure mode is emitting plausible text ("Thank you for watching.") when given silent or near-silent audio, and Free Flow currently hands the decoder *all* captured audio — no silence trimming, no no-speech gating. Model-agnostic and independent of [0021](0021_model-picker.md)/[0022](0022_transcription-eval-harness.md) ordering, though 0022's corpus is the regression instrument for the threshold choices.

## Problem

- Accidental activations are routine for a hold-to-dictate app — a brushed Right Option, a stray tap-mode toggle — and produce recordings that are entirely silence. Today those go straight to decode, where the model may invent text that is then pasted at the cursor. **Pasting words the user never spoke is the worst failure this app can produce** (the same class as the prompt-echo field bug recorded in [0008](0008_custom-dictionary-redesign.md), which was driven by the same trailing-silence mechanism).
- Every real dictation also carries trailing silence/breath after the last word — pure hallucination fodder for the decoder.
- The only `DecodingOptions` field set today is `promptTokens`. No `noSpeechThreshold`/log-prob gating, no temperature fallback for garbled segments — all upstream Whisper defaults this integration never adopted.

## Design

1. **Leading/trailing silence trim** — a pure static helper in `AudioCaptureManager` beside `convert(_:from:toSampleRate:)`: drop samples below an energy threshold at both ends, keeping a safety margin so speech onset is never clipped. Runs at stop time on the already-converted 16 kHz buffer. Thresholds and margin are `Constants` internal tunables, not settings — the user shouldn't have to reason about dBFS (the compile-time/runtime split, load-bearing rule #5).
2. **No-speech gating** — set `DecodingOptions.noSpeechThreshold` (and log-prob threshold) so silent/near-silent audio yields an *empty* result instead of hallucinated text.
3. **Temperature fallback** — adopt WhisperKit's temperature-fallback schedule for low-confidence segments, matching upstream Whisper defaults; measured before/after via 0022 so it earns its place.
4. **Quiet no-op for true silence** — session treatment: an empty transcription from an all-silence recording is "you didn't say anything," not a failure, and shouldn't raise the error glyph. Route it through the `notices` channel (or drop it silently) rather than `errors`; decide the exact surface during implementation. Constraint: `.emptyTranscription` on a recording that *did* contain speech must still surface loudly — that's a real failure.

## Acceptance criteria

1. The trim helper is pure and unit-tested on synthetic buffers: all-silence in → empty (or near-empty) out; silence-padded speech → speech preserved with margin; speech-only → untouched. Same test pattern as the existing `convert` tests.
2. An all-silence recording produces no pasted text and no error-glyph alarm (session-level test through the `.recording → .processing → .idle` cycle).
3. 0022 silence-tagged fixtures pass: silence clips decode to empty; speech clips show no WER regression from the trim or the thresholds.
4. All thresholds live in `Constants`; no new `SettingKey`s.
5. Behavior holds across the 0021 curated model list (the thresholds must not be tuned to one model).

## Related

- [0022_transcription-eval-harness.md](0022_transcription-eval-harness.md) — the silence fixtures and WER-regression instrument for every threshold here
- [0021_model-picker.md](0021_model-picker.md) — this hardening is model-agnostic and must hold across the curated list
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — where trim and decoding options land in the cycle
- [0008_custom-dictionary-redesign.md](0008_custom-dictionary-redesign.md) — historical record of the trailing-silence hallucination mechanism (the redesign itself is dropped; this spec absorbs its silence-trim and `noSpeechThreshold` ideas)
