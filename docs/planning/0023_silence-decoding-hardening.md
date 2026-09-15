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

## Field observations (2026-09-14): unwanted text appended to real dictations

**Not yet fixed. Recorded to inform the next pass on this spec.**

Two separate instances during the #30–#36 smoke testing. In both, a normal dictation pasted correctly, with extra text appended at the end that the user never said:

1. **A trailing `[BLANK_AUDIO]`** after real speech.
2. **"Thanks for watching"** after real speech, with no obvious source.

**Why the shipped 0023 work doesn't catch either:**

- `TranscriptionManager.isNonSpeechAnnotation` classifies the **whole output only**. Mixed annotation-and-speech output is deliberately left untouched, so dictation that legitimately contains brackets never loses content. A trailing `[BLANK_AUDIO]` after real words is exactly that mixed case, so it passes through.
- "Thanks for watching" contains no brackets, so no annotation filter can match it.
- The code already records that the decode gates (`noSpeechThreshold`, `logProbThreshold`, `compressionRatioThreshold`, temperature fallback) "do not reliably suppress these."

**Working hypothesis — one cause, two symptoms.** Both appear at the **end** of a recording, which points at the trailing tail: the stretch between the user finishing speaking and releasing or tapping the hotkey. That tail is room tone, breath, or keyboard noise. If it sits above the silence-trim threshold it survives into the decode, and Whisper transcribes near-silence as either an annotation or a hallucinated phrase. "Thanks for watching" is one of Whisper's best-documented hallucinations, from YouTube subtitles in its training data, and it typically appears on silent or non-speech audio. Temperature fallback on a low-confidence final segment makes hallucination more likely, not less.

**One alternative to rule out first:** the "Thanks for watching" instance happened during the same session as the #34 media-pause test, which involved a YouTube video playing near the microphone. If a video was audible while that dictation was recorded, the phrase may be real captured audio rather than a hallucination. Worth checking before designing around it.

**Candidate directions, roughly in order of preference:**

- **Filter per segment, not per output.** WhisperKit returns segments with their own no-speech probability and average log probability. Dropping a *trailing* segment that is annotation-only or low-confidence removes both symptoms while keeping bracketed words inside real speech.
- **Tighten the trailing trim** so the tail after the last speech is cut before decoding, rather than relying on a whole-clip energy threshold.
- **Avoid temperature fallback on the final segment**, where a low-confidence retry is the hallucination risk.
- **A known-phrase blocklist** ("Thanks for watching", "Subscribe", and similar). Brittle and English-specific, so a last resort, but cheap and effective against the most common offenders.

The eval harness (0022) is the instrument for any of these: add a few clips that end in a second or two of room tone and check whether output gains trailing text.

## Related

- [0022_transcription-eval-harness.md](0022_transcription-eval-harness.md) — the silence fixtures and WER-regression instrument for every threshold here
- [0021_model-picker.md](0021_model-picker.md) — this hardening is model-agnostic and must hold across the curated list
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — where trim and decoding options land in the cycle
- [0008_custom-dictionary-redesign.md](0008_custom-dictionary-redesign.md) — historical record of the trailing-silence hallucination mechanism (the redesign itself is dropped; this spec absorbs its silence-trim and `noSpeechThreshold` ideas)
