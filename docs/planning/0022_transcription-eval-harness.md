# Planning: Transcription Eval Harness (roadmap 0022)

A queued backlog item from the 2026-07-06 transcription-quality review. Build the measurement instrument for model decisions: a fixed local corpus of dictation clips with reference transcripts, plus a word-error-rate (WER) scorer, so [0021_model-picker.md](0021_model-picker.md)'s curated list and default are decided by numbers from *our* workload — short dictation clips on Apple Silicon — not by published benchmarks (which measure long-form audio) or vibes. **Posture on record:** this project uses off-the-shelf WhisperKit models as-is; it measures them, it does not modify them (no fine-tuning, no custom models, no vocabulary layers — see the drop decision in [0008](0008_custom-dictionary-redesign.md)).

## Problem

- The `small.en` default was chosen in M8 for prompt robustness plus informal accuracy. Stronger candidates (`large-v3-turbo`, `distil-large-v3`) have never been evaluated here at all, and 0021's acceptance criterion 5 ("each shipped list entry validated on-device") currently has no defined instrument — it would be a vibes check.
- The one existing eval, the env-gated `DictionaryEvalTests` A/B harness, already proved this approach pays for itself — it caught `base.en` degenerating to empty output under a prompt. But it's one clip, no reference transcripts, no scoring.
- Without a fixed corpus there is also no regression check: a WhisperKit major bump or a new model variant can only be assessed by re-dictating and squinting.

## Design

- **Local corpus, never committed.** WAV clips + hand-verified reference transcripts live in a local directory outside the repo, pointed at by an env var (e.g. `FREEFLOW_EVAL_CORPUS`), following the existing `FREEFLOW_AB_WAV` pattern. The repo is public and voice recordings are personal data — the same posture that keeps user content out of logs (anti-pattern #4). A small manifest pairs each clip with its reference text and tags (`commands`, `long-form`, `silence-heavy` — the silence tags are [0023](0023_silence-decoding-hardening.md)'s regression fixtures).
- **Env-gated swift-testing manual test**, exactly the `DictionaryEvalTests` shape (`.enabled(if:)`). The default `swift test` run and CI ([0014](0014_test-coverage-and-ci.md)) never download a model and never see the corpus.
- **Pure WER scorer** as the unit-tested core: tokenization + edit distance + the normalization rules (case, punctuation, whitespace) decided and documented in one place. No model in the loop for the scorer's own tests.
- **Per-model scorecard**: WER per clip and aggregate, transcription latency per clip, model load time, and download size, written to a results file (the `ab-result.txt` pattern). One run per candidate model name; runs are directly comparable because the corpus is fixed.

## Acceptance criteria

1. The WER scorer is a pure function with unit tests on synthetic string pairs (insertions, deletions, substitutions, normalization edge cases); runs in the default suite.
2. The harness takes any WhisperKit model name, runs the corpus, and emits a scorecard file; it is env-gated and adds zero cost to `swift test` and CI.
3. A baseline scorecard for `small.en` and scorecards for the 0021 candidate models are produced and their conclusions recorded in [0021](0021_model-picker.md) (which entries make the curated list, and whether the default moves).
4. The corpus directory format and how to run the harness are documented in [../conventions/tests.md](../conventions/tests.md); no audio or transcripts enter the repo.

## Related

- [0021_model-picker.md](0021_model-picker.md) — the consumer: scorecards decide the curated list and the default
- [0023_silence-decoding-hardening.md](0023_silence-decoding-hardening.md) — contributes silence-heavy fixtures; uses the corpus as its regression instrument
- [0014_test-coverage-and-ci.md](0014_test-coverage-and-ci.md) — CI stays model-free; the harness is manual and env-gated
- [../conventions/tests.md](../conventions/tests.md) — the env-gated manual-test pattern this extends
