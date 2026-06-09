# Planning: Model Loading Indicator (roadmap 0004)

A queued follow-up, deferred from the M8 custom-dictionary work. Surfaces the
model-loading state in the menu bar so a dictation attempted before the model is
ready gets clear feedback instead of a silent failure.

## Problem

The custom dictionary needs the model fully loaded — including the tokenizer —
before the first transcription, or the prompt is empty (see
[../requirements/custom-dictionary.md](../requirements/custom-dictionary.md)).
`TranscriptionService.loadModel()` now uses `load: true`, so the model genuinely
loads into memory at launch, and the default `small.en` (~240 MB) makes the
first-ever run longer. During that window `transcribe` fail-fasts with
`.modelNotLoaded` ("Couldn't transcribe. Transcription model is not loaded yet")
and the spoken audio is lost — while the menu bar still shows "Ready," which is a
lie until the model is warm.

The fail-fast itself is deliberate (the cycle returns to `.idle` rather than hang
— see `TranscriptionServiceTests` "model gate"), but with a real load at launch it
is now hit often enough to need a user-visible surface.

## Desired behavior ("warm vs warming up" — the cache-hit analogy)

- **Cold launch** (model not yet downloaded): status shows **"Downloading model…"**
  then **"Loading…"** — never "Ready" — until the model is in memory. First run
  only (~240 MB).
- **Warm launch** (model already downloaded): **no re-download**; a brief
  **"Loading…"** while CoreML loads it into memory, then **"Ready."** (Each process
  start re-loads into memory — a few seconds — so "Ready" follows a short load, not
  literally zero delay.)
- Dictating before "Ready" gives clear feedback (the status already shows it isn't
  ready) and ideally either waits for the load or declines to start recording,
  rather than record-then-error and lose the audio.

## Mechanism (sketch)

- `TranscriptionService` exposes a load state (e.g. `downloading / loading / ready
  / failed`), distinguishing download from in-memory load.
- `AppState` observes it via the existing Combine→`@Observable` bridge, and
  `MenuBarPresentation` maps it to the icon/label — extending the menu-bar layer
  from the visual-state milestone
  ([../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)).
- Optionally gate recording start on `ready` (or have `transcribe` await an
  in-flight load) — a deliberate change to the current fail-fast contract; decide
  during implementation.

## Acceptance criteria

1. A launch with an uncached model shows a downloading/loading status, not "Ready,"
   until the model is in memory.
2. A cached launch never re-downloads, shows a brief loading state, and reaches
   "Ready" promptly.
3. Dictating during load produces clear feedback (and no silently lost audio)
   rather than the bare `.modelNotLoaded` error.
4. The load-state → label mapping is unit-tested (pure, like `MenuBarPresentation`).

## Related

- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the status surface this extends
- [../requirements/custom-dictionary.md](../requirements/custom-dictionary.md) — why the model (tokenizer) must be loaded before the first prompt
- [milestones.md](milestones.md) — the roadmap this is queued in
