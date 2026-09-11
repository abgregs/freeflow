# Planning: Model Switch Availability & Download Management (roadmap 0026)

From the 2026-08-18 on-device smoke of 0004/0021/0002 (the first real-device pass over the model picker + HUD): switching models works, but the *availability model* around it is stricter than it needs to be, and two robustness gaps surfaced in the field. A cached model should be usable near-instantly regardless of what else is downloading; an in-flight download should survive being deselected; and the cache/failure edges found during the smoke need hardening.

## Problem

Four field findings, one theme — the current design serializes everything through a single active-model pipeline:

1. **Switch-back waits on nothing.** Select Distil (starts a ~1.4 GB download), change your mind, re-select the already-downloaded Base: the correct behavior is dictation available as soon as Base's seconds-long in-memory load completes. Today the experience is opaque at best; the single `loadGeneration` line and cancelled tasks make "the cached model is right there" indistinguishable from a cold download.
2. **Deselecting cancels the download.** `prepareModelSwitch` cancels the in-flight load task, throwing away partial progress (cancellation is cooperative, so it may also silently *continue* — untracked either way). The user's intent when switching away mid-download is almost never "discard that"; the download should complete in the background so the model is cached for next time.
3. **`isModelCached` trusts a partial directory.** The AudioEncoder-presence heuristic misclassified an interrupted download's leftovers (a 1.3 MB `base.en` dir, observed 2026-08-14) — the label side is cosmetic, but 0026's availability decisions ("cached ⇒ usable now") make correctness load-bearing.
4. **`.failed` is a dead end.** A failed load requires relaunch: the same-model no-op guard in `prepareModelSwitch` blocks re-picking as a retry, the HUD deliberately doesn't surface `.failed` (a permanent floating panel would nag — decided in 0002/0018 follow-through), and there is no retry affordance anywhere.

Also folded in (trivial, same surface): the picker's size hints understate real on-disk footprints ~2× (e.g. "~600 MB" vs 1.4 GB measured); 0022's scorecards report exact sizes — use those numbers.

## Design sketch

- **Per-model tracking replaces the single pipeline.** `TranscriptionManager` (or a small extracted download manager it owns) tracks download/load state *per model name*, so "what is the active model doing" and "what is fetching in the background" are separate questions. The published `ModelLoadState` stays the *active* model's state — the HUD/menu contract from 0004 is unchanged.
- **Cached ⇒ available.** A switch to a fully-cached model loads it immediately and publishes `.loading → .ready` on the active channel, regardless of background fetches. The activation gate (0004) then unblocks in seconds, not after unrelated downloads.
- **Deselected downloads continue.** At most the one in-flight background download keeps running to completion (no queue — switching away twice mid-download drops the older fetch); on completion it updates the per-model cache state only, never the active model's published state (the `loadGeneration` supersession rule generalizes to "background results never touch the active channel").
- **Cache verification.** `isModelCached` verifies the full required file set (or delegates to WhisperKit's own manifest check) instead of one file's presence; a partial directory reads as *not cached* and a fresh fetch cleans it up.
- **Failed-state recovery.** Re-picking the failed model retries (the no-op guard yields when the state is `.failed`); the failure surfaces once as a HUD toast (the 0018 surface — "Model failed to load — pick it again to retry") rather than pinning the panel.

Session-side contracts are untouched: switches still apply only at `.idle` (deferred otherwise), and recording is still gated on the *active* model being `.ready`.

## Acceptance criteria

1. With a background download in flight, switching to a fully-cached model reaches `.ready` (and dictation unblocks) without waiting on the download — asserted with fake decode/load seams, no real network.
2. Switching away from a mid-download model does not cancel it; when it completes, the model reads as cached and a later switch to it needs no download. The completion never mutates the active model's published `ModelLoadState`.
3. `isModelCached` returns false for a partial model directory (fixture: a dir containing only a config-sized subset) and true for a complete one.
4. Re-picking a model whose load `.failed` retries the load; the failure emits a one-shot toast on the HUD instead of a pinned panel.
5. Picker size hints match 0022 scorecard on-disk measurements, and heavy-model hints mention that the first load takes minutes (CoreML compilation).

## Related

- [0021_model-picker.md](0021_model-picker.md) — the switch mechanics this loosens; curated list/default still decided by 0022 scorecards
- [0004_model-loading-indicator.md](0004_model-loading-indicator.md) — the `ModelLoadState` contract 0026 preserves (active-model channel only)
- [0022_transcription-eval-harness.md](0022_transcription-eval-harness.md) — source of the true size numbers for AC5
- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) / [0018_transient-error-toasts.md](0018_transient-error-toasts.md) — the HUD/toast surfaces AC4 uses
- [../architecture/river-session.md](../architecture/river-session.md) — the idle-only reconfiguration contract, unchanged
