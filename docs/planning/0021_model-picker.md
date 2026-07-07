# Planning: Model Picker in Settings (roadmap 0021)

Promotes the long-standing "Model picker in Settings" open item ([_index.md](_index.md)) to a spec, prompted by the 2026-07-06 UX review. Let the user choose the WhisperKit model — speed-focused users drop to `base.en`; future multilingual models get a path in. **Build [0004_model-loading-indicator.md](0004_model-loading-indicator.md) first** — a model switch re-enters exactly the download/load window 0004 makes visible. **Rescoped by the 2026-07-06 transcription-quality review:** the curated list and the default are decided by [0022](0022_transcription-eval-harness.md)'s scorecards, and the candidates must include the stronger models (`large-v3-turbo`, `distil-large-v3`) that have never been evaluated here — a plausible outcome is a default bump that ships ahead of (or without) the picker UI, if the eval shows one clear winner rather than tradeoffs worth exposing.

## Problem

The model is hard-coded: `TranscriptionService.init(modelName: String = Constants.defaultModel)` with `small.en` (~240 MB). [../architecture/configuration.md](../architecture/configuration.md) already tables `selectedModel` (`String`, default `Constants.defaultModel`, consumer `TranscriptionService`) as landing "with the model picker" — the key deliberately does not exist yet (no inert settings; anti-pattern #5's cousin, see [0003](0003_pause-media-while-dictating.md) for the same posture). `small.en` is the right default for accuracy, but it's a real cost in first-download size and per-dictation latency that some users would happily trade down.

## Design

- **`Settings.selectedModel`** (`String`, default `Constants.defaultModel`) declared once (anti-pattern #8), plus a **curated model list in `Constants`** (a vetted list, not a free-text field; each entry earns its place via a [0022](0022_transcription-eval-harness.md) scorecard before joining the list).
- **Picker in `SettingsView`** with a one-line size/speed/accuracy hint per model, following the activation-mode picker's pattern.
- **`TranscriptionService` subscribes and reloads off-cycle:** apply a model switch only from `.idle`; a change mid-`.recording`/`.processing` defers to the next `.idle` — mirroring the session's apply-or-defer contract so a switch can never corrupt an in-flight cycle. The reload path reuses `loadModel()`'s existing coalescing.
- **The switch re-enters 0004's load state** (`downloading`/`loading`, possibly a first-time download for the new model) — the menu bar/HUD must show it, never a false "Ready." This is the hard dependency on 0004.
- **Disk footprint decision:** switching leaves the previous model cached under `~/Library/Application Support/FreeFlow` ([0010](0010_relocate-model-cache.md)). Decide whether to keep both (fast switch-back; ~380 MB for two) or offer cleanup; the Homebrew cask `zap` already removes the whole cache dir.

## Interplay to watch

- **Custom dictionary redesign ([0008](0008_custom-dictionary-redesign.md)) — dropped 2026-07-06:** the redesign is dropped (see 0008's status), so the earlier constraint that prompt biasing requires `small.en` no longer shapes the model list. The prompt plumbing remains in `TranscriptionService` with no consumer.
- **Silence & decoding hardening ([0023](0023_silence-decoding-hardening.md)):** its thresholds must hold across every model on the curated list (0023 acceptance criterion 5) — adding a list entry means re-running its 0022 silence fixtures under that model.

## Acceptance criteria

1. The picker lists the curated models; selecting one persists via `SettingsStore` and reloads the model without an app restart.
2. A switch mid-cycle defers to `.idle` (unit-tested); a switch at `.idle` applies immediately.
3. During the switch, the status surface shows the 0004 load states — never "Ready" with a stale or absent model — and dictation during the load gets 0004's clear feedback.
4. `SettingsStore` round-trip and publisher-dedupe tests for the new key; `TranscriptionService` reload-on-change tests reuse the load-coalescing seam.
5. Each shipped list entry has a [0022](0022_transcription-eval-harness.md) scorecard (WER, latency, load time, size) plus an on-device sanity check.

## Related

- [0022_transcription-eval-harness.md](0022_transcription-eval-harness.md) — decides the curated list and the default; build first
- [0004_model-loading-indicator.md](0004_model-loading-indicator.md) — hard dependency: makes the switch window visible
- [0023_silence-decoding-hardening.md](0023_silence-decoding-hardening.md) — thresholds must hold across the curated list
- [0010_relocate-model-cache.md](0010_relocate-model-cache.md) — where model files live; the disk-footprint decision
- [../architecture/configuration.md](../architecture/configuration.md) — already tables `selectedModel`; update it when the key lands
