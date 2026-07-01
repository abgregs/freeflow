# Planning: Test Coverage & CI Execution (roadmap 0014)

A testing-focused review of the suite found it **healthy, not test theater** — 99 tests that drive real production paths through internal seams that stub *infrastructure* (the OS/network calls that can't run in CI: `CGEvent.post`, `AVAudioEngine.start`, `CGEventTap`, the WhisperKit model load), not the logic under test. The load-bearing bug classes from the predecessor app — silent paste failure, mid-recording state corruption, lying permission checks — each have a test that would fail on a real regression.

The same review surfaced **one process gap and four content gaps**. They build on top of the existing [tests.md](../conventions/tests.md) conventions — this spec is the punch list to close the holes that doc's "what is and isn't testable" table leaves open. It adds **no new product behavior**; it hardens the test/CI surface around behavior that already ships. Ordered by leverage.

## 1. No CI runs the suite — highest leverage

**Observed.** `.github/workflows/` contains only [`release.yml`](../../.github/workflows/release.yml), which fires on a `v*` tag and builds → signs → notarizes. The **only** `swift test` invocation in the repo is the `make test` target, run by a developer by hand. Nothing runs the 99 tests on a push or a pull request.

**Why it matters.** Branch protection ("Protect main branch") requires a PR + code-owner review, but **not** a passing test run — so a change that reds the entire suite merges green as long as a human approves the diff. The suite's value is capped at "whoever remembered to run it locally."

**Proposed fix.** Add a CI workflow (e.g. `.github/workflows/ci.yml`) that runs `swift test` on `pull_request` and on `push` to `main`, then register it as a **required status check** on the protected `main` ruleset so a red suite blocks merge.

- **Runner parity with release.yml.** `macos-15` (Apple Silicon); select the newest *stable* Xcode so the Swift toolchain is ≥ 6.2 (the WhisperKit dependency requires it — same step release.yml already performs). Pin every action to a full commit SHA and use least-privilege `permissions:` ([0005](0005_release-pipeline-security.md) workflow hardening).
- **Already CI-safe.** [tests.md](../conventions/tests.md) isolation rules guarantee the suite needs no microphone / Accessibility / network grant, so it runs on a clean runner. `DictionaryEvalTests` auto-skips (it's `.enabled(if: FREEFLOW_AB_WAV)`, unset in CI) and the one `.disabled` `endToEndPasteCycle` test stays disabled — both already exclude themselves.
- **The cost is the build, not the tests.** Building WhisperKit from source is heavy; cache the SwiftPM `.build` / dependency cache keyed on `Package.resolved` so steady-state runs are fast.

## 2. The transcription empty-prompt retry fallback is unasserted

**Observed.** `TranscriptionService.transcribe(audioSamples:)` contains the dictionary-can-only-help guarantee: `if text.isEmpty, !promptTokens.isEmpty { retry unprompted }`. A small model conditioned on a custom-dictionary prompt can emit empty output; without this retry, adding a dictionary term would turn a *working* dictation into a hard `.emptyTranscription` — strictly worse than no dictionary ([custom-dictionary.md](../requirements/custom-dictionary.md)). This branch is exercised **only** by the env-gated, live-model `DictionaryEvalTests` harness; the normal suite never asserts it. Dropping the retry, or inverting the guard, would pass every CI test today.

**Why it's untested.** The retry calls the `private func decode(...)` → `whisperKit.transcribe(...)`, and there is no model in CI ([ADR 0001](../decisions/0001-defer-cycle-protocol-seams.md)).

**Proposed fix (ADR-0001-consistent).** Introduce a **narrow decode seam inside `TranscriptionService`** — not a `Transcriber` protocol. Either inject the decode step as a closure defaulting to the real WhisperKit call, or lift the prompted→empty→unprompted *decision* into a pure helper that takes a `(promptTokens: [Int]) async throws -> String` and applies the retry rule. A test then supplies a fake decode returning `""` for the prompted call and `"hello"` for the unprompted call, and asserts:
- the unprompted retry fires and its text is returned (the dictionary degraded to neutral, not to an error);
- a genuinely silent recording (both decodes empty) still throws `.emptyTranscription` (honest failure preserved).

No model required. This keeps ADR 0001's "seam named, just not promoted" stance.

**ADR 0001 interaction — decide consciously when scheduling.** This gap *and* the already-`.disabled` `endToEndPasteCycle` success-path test are two consumers wanting an injectable transcription seam — the ADR's "**revisit if… cycle tests start needing to inject success-path scenarios**" trigger. The narrow decode seam closes *this* gap without the protocol. If the full success-path paste-cycle test is also wanted, that is the deliberate moment to revisit ADR 0001 and extract `Transcriber`. Pick one when this item is picked up; don't extract the protocol speculatively.

## 3. `AppState.bind(to:)` — the session→UI wiring — is untested

**Observed.** `AppState.bind(to:)` subscribes `session.state`, `session.errors`, and `session.notices` to the three `apply` entry points. The `apply` methods are unit-tested directly ([AppStateTests](../../Tests/FreeFlowTests/AppStateTests.swift)), but nothing asserts `bind` actually connects the publishers — a dropped `.sink` or a mis-wired publisher would pass every existing test while the menu bar silently stops updating.

**Proposed fix.** No new seam needed. Construct a real `FreeFlowSession` (the `FreeFlowSessionTests` `makeSession` harness) plus an `AppState`, call `bind(to:)`, drive a cycle (`handleActivate`; a mid-recording settings change for a notice; a no-buffer deactivate for an error), and assert `appState.state`, `appState.errorMessage`, and `appState.notice` all track — including the notice's clear-on-end lifecycle. Exercises all three subscriptions end-to-end.

## 4. `AudioCaptureManager.convert`: error paths and content correctness untested

**Observed.** The `conversionFailed` branch (converter-init / convert error in `convert(_:from:toSampleRate:)`) is never exercised, and every existing `convert*` test feeds **silent zero buffers**, so only length/plumbing is verified — not that samples are actually downsampled. A converter that silently produced zeros of the right length would pass.

**Proposed fix.**
- Feed an input the converter can't build or run (e.g. an incompatible / zero-channel format) and assert `.conversionFailed` propagates.
- Feed a **non-silent** synthetic signal (a sine at a known frequency/amplitude) and assert the 16 kHz output is non-trivial — RMS > 0 and length within the documented resampler-latency window. Assert **energy/shape, not sample equality**: exact-match is brittle against `AVAudioConverter` latency (the existing length tests already use tolerance windows for this reason).

## 5. Minor unexercised branches + one dead assertion

Cheap, pure-function coverage plus a cleanup:

- **`SettingsStore.readValue` undecodable fallback** — a stored value that is neither directly castable nor `DefaultsConvertible` returns the default. Write a wrong-typed value into a per-test suite and assert the default comes back.
- **`TapStateMachine.reset()`** — no test exercises it. Assert it returns the machine to its start state and produces no spurious deactivate.
- **`ActivationNotice.keyChanged` unknown-keycode fallback** — the `?? "the new key"` path (a keycode absent from `ActivationKeyOption.all`) is untested; assert the generic phrasing.
- **Cleanup — delete a dead assertion.** `TextInsertionManagerTests.keepsGraphemesIntact` contains `$0.unicodeScalars.allSatisfy { _ in true }`, which can never be false; the adjacent `== ["👍", "👍"]` is the real check. Remove the tautology.

## Scope / non-goals

- **True end-to-end** (real model + real audio + a real paste into a real app) stays **manual on-device, pre-release**, per [tests.md](../conventions/tests.md)'s testability table and the `.disabled` `endToEndPasteCycle` placeholder. Not in scope here.
- **SwiftUI view / snapshot tests** (`OnboardingView`, `SettingsView`) remain out of scope; only the pure presentation mappings are unit-tested, by design.
- A few **table-shape change-detector** tests (`ActivationModeTests.tableComplete`, `ActivationKeyOptionTests.tableComplete`, `MenuBarPresentationTests.visualPerState`) assert literals hardcoded in both test and source. They are low-signal but cheap and honestly commented; **not** slated for removal here — noted so a future reader knows the assessment was deliberate.

## Acceptance criteria

1. A CI workflow runs `swift test` on every PR and on push to `main`, and is a **required status check** on the protected `main` ruleset (a red suite blocks merge). The runner mirrors release.yml: macOS, stable Xcode ≥ Swift 6.2, SHA-pinned actions, least-privilege `permissions`, SwiftPM cache.
2. A unit test drives the transcription empty-prompt retry **without a live model**: prompted-empty → unprompted retry returned; both-empty → `.emptyTranscription`. Implemented via a narrow decode seam, with no `Transcriber` protocol unless the ADR-0001 revisit is taken deliberately.
3. A test binds a real `FreeFlowSession` to an `AppState` via `bind(to:)` and asserts `state`, `errorMessage`, and `notice` all propagate (including notice clear-on-end).
4. Tests exercise `AudioCaptureManager.convert`'s `conversionFailed` path and assert non-zero downsampled output for a non-silent input.
5. Tests cover `SettingsStore.readValue`'s undecodable fallback, `TapStateMachine.reset()`, and `ActivationNotice.keyChanged`'s unknown-keycode fallback; the dead assertion in `TextInsertionManagerTests` is removed.
6. Any new seam introduced (e.g. the transcription decode seam in #2) is added to the access-seams inventory in [tests.md](../conventions/tests.md) so that list stays the single source of truth.

## Related

- [../conventions/tests.md](../conventions/tests.md) — testing conventions, the what-is/isn't-testable table, and the access-seams inventory this spec extends
- [../decisions/0001-defer-cycle-protocol-seams.md](../decisions/0001-defer-cycle-protocol-seams.md) — the ADR the transcription decode seam (#2) presses on; its "revisit if… success-path injection" trigger
- [../architecture/release-pipeline.md](../architecture/release-pipeline.md) and [`../../.github/workflows/release.yml`](../../.github/workflows/release.yml) — the runner, toolchain, and hardening the CI job (#1) mirrors
- [../conventions/git.md](../conventions/git.md) — branch protection; the test job becomes a required check
- [../requirements/custom-dictionary.md](../requirements/custom-dictionary.md) — the "a dictionary term can only ever help" guarantee behind #2
