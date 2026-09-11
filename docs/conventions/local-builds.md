# Conventions: Local Builds and On-Device Smoke

How to get a trustworthy dev build onto this machine and verify a PR against it. Written after two review cycles lost time to the same avoidable problems: smoking a stale branch, and mistaking a normal model load for a hang.

## The sequence

Run these in order. Each step exists because skipping it has produced a wrong result at least once.

```bash
# 0. Quit the app if it is running (see below — never rm -rf a live bundle)

# 1. Work from the worktree root, not with `git -C <path>`
cd ~/Developer/river-stack/<worktree>

# 2. Refresh the branch with main FIRST (maintainer-run — merges are not automated)
git merge origin/main

# 3. Remove the released cask so it can't shadow the dev build
brew uninstall --cask river

# 4. Build, bundle, sign, install
make install
```

**Run these from the worktree root.** The `git -C <absolute path> …` form has failed to take effect here in practice; `cd` first, then run the bare command.

### Refresh before you build — not after

A stacked branch is based on its parent, not on `main`. Smoking it un-refreshed tests a base that no longer exists.

This has bitten twice. A `feat/0002-0018-0020` build once pasted `[BLANK_AUDIO]` because it predated the non-speech annotation filter that had already merged. Later, PR #30's on-device smoke ran 17 commits behind `main`, missing both the annotation filter and two commits that changed how load-state is emitted through `AppState` — the exact seam the feature under test observed. The smoke passed and told us nothing about the code that would actually land.

**Verify before building:**

```bash
git rev-list --left-right --count origin/main...<branch>
```

The left number is how many commits `main` has that the branch doesn't. It must be `0` before an on-device smoke means anything. The right number — commits the branch has that `main` doesn't — is just the branch's own work and is expected to be non-zero.

**Verify the branch you will actually build from**, which is not necessarily the one you reviewed in. In a stacked review it is normal to read a *combined* diff from the upper worktree (so the lower PR's commits appear on a current base) while the lower PR's own branch sits far behind. Refreshing one worktree does nothing for its sibling. This bit us on #31: the review happened in a clean g10 while g09 — the branch that would actually be built and merged — was 18 commits behind.

### Quit the app before installing

`make install` does `rm -rf` on `/Applications/River.app`. Doing that to a running app deletes the bundle out from under a live process, and since the silent-no-op detector keys off bundle identity, that is a good way to manufacture a confusing false negative that looks like a permissions regression.

### Clean slate before install

If the Homebrew cask is installed, `/Applications/River.app` belongs to it. Removing it first eliminates any ambiguity about which binary is running and which bundle holds the TCC grants. Cheap step; do it first rather than debugging a shadowed build later.

### Expect one permission round-trip per rebuild

Each `make install` re-signs with the self-signed "River Dev" identity, so macOS treats the bundle as a changed binary. Accessibility typically needs one Grant → Refresh round-trip before the app's own launch-time read reports `.granted`. The TCC row survives; the app-side read is the false negative. This is what planning 0012 (PR #33) addresses — until it lands, treat one round-trip as expected, not as a regression.

## "Loading model…" is not downloading

**This is the single most misread signal in local builds.** The indicator covers both operations, and they have completely different causes and costs.

`make install` does exactly two things:

```make
rm -rf $(INSTALL_DIR)/$(APP_NAME).app
cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_NAME).app
```

It **never touches** `~/Library/Application Support/River`. Downloaded models always persist across installs — the sandbox is intentionally off, so the cache lives outside the app container (see [../architecture/distribution.md](../architecture/distribution.md)).

So a long "Loading model…" after a rebuild is **not** a re-download. It is CoreML loading the model and compiling it for the Apple Neural Engine. On a 1.5 GB model this legitimately takes long enough to look like a hang.

### Before concluding it is stuck

Three checks, in increasing order of effort. Do them before deleting anything.

```bash
# Is anything actually being downloaded? (no output = no partial downloads)
find ~/Library/Application\ Support/River -name "*.incomplete" -o -name "*.part"

# Has anything been written recently? (no output = nothing is downloading)
find ~/Library/Application\ Support/River -type f -newermt '-1 hour'

# What is the process actually doing?
sample $(pgrep -f "River.app/Contents/MacOS/River") 3
```

In the sample, a **healthy load in progress** looks like: main thread parked in `__CFRunLoopServiceMachPort` (idle, waiting for events) while background threads carry `Espresso`, `ANECompiler`, `ANEServices`, and `MLModelAsset` frames. Espresso is CoreML's execution engine; `ANECompiler` frames mean the Neural Engine compile is running. That is work, not a deadlock.

A genuine hang would show the main thread blocked in app code, or no CoreML activity at all.

### Do not delete the model cache to "fix" a slow load

It costs you twice: a full re-download **and** the identical ANE compile afterward. You wait strictly longer and land in the same place. The cache is only worth clearing if a check above shows actual corruption — partial files, or a model directory missing one of its four `.mlmodelc` bundles (`AudioEncoder`, `MelSpectrogram`, `TextDecoder`, `TextDecoderContextPrefill`).

### Pick a small model for mechanics smoke

Load time scales with model size:

| Model | On-disk size |
|---|---|
| `openai_whisper-base.en` | ~140 MB |
| `openai_whisper-small.en` | ~464 MB (the default) |
| `distil-whisper_distil-large-v3` | ~1.4 GB |
| `openai_whisper-large-v3-v20240930_turbo` | ~1.5 GB |

When smoking anything **other than transcription quality** — cancel gestures, clipboard behavior, permissions, sound cues, HUD states — transcription accuracy is irrelevant. You only need words to come out. Use `base.en` and every rebuild gets dramatically cheaper.

Switch it in Settings → Transcription → Model, or out-of-band with the app quit:

```bash
defaults write com.river.app selectedModel openai_whisper-base.en
```

Evaluating models is a separate activity with its own instrument — the eval harness (planning 0022) — not something to do by ear during a feature smoke.

### "Loading" is the wrong word for what is happening

The `.mlmodelc` files on disk are CoreML's *portable, architecture-neutral* compiled format. They are not an executable program for the Neural Engine. Preparing one means **translating** it into an ANE-specific program — weights re-laid-out for ANE memory, operations fused and scheduled for that silicon. The download supplies the recipe; this step builds the thing that actually runs.

That gap is why the indicator misleads. "Loading" implies reading bytes into memory, an operation whose duration scales with size in a way people intuitively expect. What actually happens is closer to **building** or **compiling**, and it can take minutes on a large model. Someone who reads "Loading…" and waits two minutes reasonably concludes the app has hung — which is exactly what happened to the maintainer on a `large-v3-turbo` build.

Wording like "Preparing model…" or "Optimizing for this Mac…" would set the correct expectation at zero engineering cost. Tracked as a copy refinement under planning 0004.

### It is once per installed *version*, not once ever

Worth stating precisely, because the imprecise version invites the wrong conclusion. The ANE-compiled artifact is cached by the OS keyed partly on the requesting binary, so **every new version a user installs plausibly pays the cost again on first launch** — not just the very first install.

This matters more than it sounds once auto-update ships (planning 0009): users who currently install once will start updating regularly, and each update may land them on a slow first launch with a misleading "Loading…" label. Small default model plus honest copy is what keeps that from reading as "the update broke it."

### Recorded but not taken: forcing GPU over the Neural Engine

WhisperKit 0.18.0 exposes per-component compute units via `ModelComputeOptions` (`melCompute`, `audioEncoderCompute`, `textDecoderCompute`, `prefillCompute`). `TranscriptionManager` passes none, so it takes the defaults — `textDecoderCompute: .cpuAndNeuralEngine`, with the audio encoder ANE-bound on capable hardware.

Forcing `.cpuAndGPU` would **skip ANE compilation entirely** and load far faster.

**Deliberately not doing this.** The ANE is both faster and far more power-efficient at inference than the GPU on Apple Silicon, so it trades a one-time startup cost for a permanent per-dictation and battery cost — a bad trade in a menu-bar app that runs all day. Recorded so the option is not rediscovered and re-litigated. If it is ever revisited, measure it with the eval harness (planning 0022) rather than by feel.

### Open question: is the ANE compile cached across installs?

Unresolved. Each `make install` produces a new code signature, and CoreML's compiled artifacts are cached by the OS keyed partly on the requesting binary, so a re-sign plausibly forces recompilation on first launch. Not confirmed.

**To settle it:** after a `make install`, time the first launch, then quit and relaunch without reinstalling and time that.

- Second launch much faster → the compile is cached, and only the first launch after each install pays it. A build-workflow cost, not a product one.
- Both equally slow → every launch pays it, which is a genuine first-run concern for any large default model.

Record the answer here once measured.

## Product signal worth escalating

If a large model takes long enough to prepare that it reads as a hang **to the people who wrote the app**, a first-time user on that default would conclude it is broken and quit.

Two consequences for the backlog:

- Argues for keeping a small shipped default, with large models as an explicit opt-in (planning 0021's default decision, pending 0022's scorecards).
- The indicator **already** distinguishes downloading from loading — `TranscriptionManager` splits the two deliberately (`load: false` to download or locate the files, then `emitLoadState(.loading)`, then `loadModels()`). The remaining gap is not the distinction but the *expectation*: "Loading…" gives no sense that a 1.5 GB model may take a long time, which is why it reads as a hang. Setting duration expectations is the open 0004 refinement, not separating the phases.

## Related

- [../architecture/distribution.md](../architecture/distribution.md) — bundle ID, signing identities, where the model cache lives and why
- [anti-patterns.md](anti-patterns.md) — #3 (bundle integrity: `Info.plist` and `--entitlements` are mandatory at sign time)
- [git.md](git.md) — stacked-branch targeting and what touches `main`
- [../planning/0012_onboarding-permissions-polish.md](../planning/0012_onboarding-permissions-polish.md) — the permission round-trip this doc treats as expected
- [../planning/0022_transcription-eval-harness.md](../planning/0022_transcription-eval-harness.md) — the right instrument for model comparison
