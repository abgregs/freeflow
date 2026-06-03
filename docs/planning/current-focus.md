# Planning: Current Focus

What's actively in flight. Update this when you start or finish a milestone.

## Status

**M6 complete** (2026-06-03). WhisperKit 0.18.0 integrated. `TranscriptionService` exposes explicit `loadModel()` (idempotent, coalesces concurrent callers) and `transcribe(audioSamples:) -> String`; `customDictionaryTerms` is a property + setter ready for M8 to wire `Settings.customDictionaryTerms`. The load-bearing **`filterSpecialTokens(_:specialTokenBegin:)`** static helper drops timestamp / language / sentinel tokens before they corrupt `DecodingOptions.promptTokens`. `AppDelegate` fire-and-forgets `loadModel` at launch on its own Task — first run downloads ~140 MB for `base.en` to WhisperKit's cache (`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/`). `FreeFlowSession.handleDeactivate` calls `transcribe` after `stopRecording` in a nested catch — audio and transcription failures are independent; either path still returns to `.idle` and applies pending reconfig. Typed errors: `TranscriptionError.modelNotLoaded` / `.transcriptionFailed(underlying:)` / `.emptyTranscription`. M6 deliberately keeps the explicit lifecycle (no `skipModelLoadForTesting` flag) — see [ADR 0001](../decisions/0001-defer-cycle-protocol-seams.md). Verified: build + 47 tests green, plus on-device end-to-end (Right Option → recording → transcribed-char log in `log stream`).

**M5 complete** (2026-06-02). `MicrophoneCapability` owns `AVAudioEngine` start/stop and exposes an `audioBuffers` publisher. `AudioCaptureManager` subscribes during `.recording`, waits up to 300 ms for the first buffer (engine-warmup race), then converts hardware-format buffers to 16 kHz mono Float32 via `AVAudioConverter`. `FreeFlowSession.handleDeactivate` is async: `.recording → .processing → .idle`. The M3 deferral loop closes here too — `pendingReconfiguration` fires on every return to `.idle`.

**M4 complete** (2026-06-01). `InputMonitoringCapability` owns the system-wide `CGEventTap` on a dedicated `com.freeflow.eventtap` background thread; the C tap callback hops to the main actor before publishing `TapEvent`s. `HotkeyManager` interprets `.flagsChanged` for the watched keycode (Hold mode only — tap modes in M9) and fires semantic `onActivate`/`onDeactivate`. Default key Right Option (keycode 61).

**M3 complete** (2026-06-01). `FreeFlowSession.start` subscribes to `SettingsStore` publishers via `subscribeToConfiguration()`; `applyOrDeferReconfiguration` applies directly when idle and parks the change in `pendingReconfiguration` otherwise. `stop` clears the subscription set.

**M2 complete** (2026-05-29). Capability layer real, onboarding end-to-end: honest `.granted`/`.denied`/`.unknown` from non-prompting status APIs; `OnboardingView` iterates `[any Capability]` with Grant/Refresh/Skip; gate via `OnboardingGate.shouldPresent(for:)`.

**M1 complete** (2026-05-26). Architectural skeleton (Swift package, `MenuBarExtra`, `FreeFlowSession`/`Capability`/`SettingsStore` stubs) plus the bundle → sign → install pipeline.

## Next up

[M7: Text insertion](milestones.md#m7-text-insertion). `AccessibilityCapability.postKeyEvent(...)` becomes the only path that calls `CGEvent.post`. `TextInsertionManager` saves the pasteboard, writes the transcription, asks the capability to synthesize ⌘V, then restores the original pasteboard after `Constants.clipboardRestoreDelay` (default 250 ms). Capability includes the silent-no-op detector for the TCC bundle-misidentification failure mode. `FreeFlowSession.handleDeactivate` hands the transcribed text to the manager (replacing M6's char-count log). Diagnostic logging available behind `--debug true`. Run `/brief` before starting.

## Working agreement

- Before any non-trivial code change: run `/brief` to find applicable conventions.
- After any non-trivial code change: run `/debrief` to keep docs aligned.
- Commit using conventional commits (see [../conventions/git.md](../conventions/git.md)).
- Don't push to `main` directly. PRs only.

## Notes for the agent picking this up

- The architecture docs encode hard-won lessons from a predecessor implementation. Treat the **Why:** annotations seriously — they exist because someone got bitten.
- The most common failure mode in this app's lineage is infrastructure that *looks* like it works but silently doesn't (a tap that fires but a paste that's blocked; a bundle that signs but has no identifier). Verify with `codesign -dv`, log inspection, and end-to-end tests in a real text field — not just "swift build succeeded."
- If you find a gap in the docs while working, flag it in `/debrief` rather than just plowing through. The docs are designed to evolve with the code.
