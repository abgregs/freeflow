# Planning: Current Focus

What's actively in flight. Update this when you start or finish a milestone.

## Status

**M5 complete** (2026-06-02). `MicrophoneCapability` owns `AVAudioEngine` start/stop and exposes an `audioBuffers` publisher — the tap callback deep-copies each buffer and hops to the main actor via `Task { @MainActor in ... }`. `AudioCaptureManager` subscribes to the stream during `.recording`, waits up to 300 ms for the first buffer (engine-warmup race fix), then converts collected hardware-format buffers to 16 kHz mono Float32 via `AVAudioConverter` and returns `[Float]`. `FreeFlowSession.handleDeactivate` is now `async`: `.recording → .processing → .idle`, with the captured sample count logged or an `AudioCaptureError` (`.noAudioCaptured` / `.conversionFailed`) surfaced via `os.Logger.error`. The M3 deferral loop closes here too — `pendingReconfiguration` fires on every return to `.idle`. Verified: build + 42 tests green, plus on-device end-to-end (Right Option drives a full cycle with captured-sample log visible in `log stream`).

**M4 complete** (2026-06-01). `InputMonitoringCapability` owns the system-wide `CGEventTap` on a dedicated `com.freeflow.eventtap` background thread (QoS `.userInteractive`); the C tap callback decodes events and hops to the main actor via `Task { @MainActor in ... }` before publishing `TapEvent`s. `HotkeyManager` interprets `.flagsChanged` for the watched keycode (Hold mode only — tap modes land in M9) and fires semantic `onActivate`/`onDeactivate`. Default activation key is **Right Option** (keycode 61).

**M3 complete** (2026-06-01). `FreeFlowSession.start` subscribes to `SettingsStore` publishers via `subscribeToConfiguration()`; `applyOrDeferReconfiguration` applies directly when idle and parks the change in `pendingReconfiguration` otherwise. `stop` clears the subscription set.

**M2 complete** (2026-05-29). Capability layer real, onboarding end-to-end: honest `.granted`/`.denied`/`.unknown` from non-prompting status APIs; `OnboardingView` iterates `[any Capability]` with Grant/Refresh/Skip; gate via `OnboardingGate.shouldPresent(for:)`.

**M1 complete** (2026-05-26). Architectural skeleton (Swift package, `MenuBarExtra`, `FreeFlowSession`/`Capability`/`SettingsStore` stubs) plus the bundle → sign → install pipeline.

## Next up

[M6: Transcription](milestones.md#m6-transcription). Integrate WhisperKit. `TranscriptionService.transcribe(audioSamples:)` returns text or a typed error; default model loads on its own schedule (not blocking the session). Custom dictionary integration with the special-token filter (`tokenizer.specialTokens.specialTokenBegin`) in place. `FreeFlowSession` calls the service during `.processing` (replacing M5's sample-count log) and continues to return to `.idle`. Run `/brief` before starting.

## Working agreement

- Before any non-trivial code change: run `/brief` to find applicable conventions.
- After any non-trivial code change: run `/debrief` to keep docs aligned.
- Commit using conventional commits (see [../conventions/git.md](../conventions/git.md)).
- Don't push to `main` directly. PRs only.

## Notes for the agent picking this up

- The architecture docs encode hard-won lessons from a predecessor implementation. Treat the **Why:** annotations seriously — they exist because someone got bitten.
- The most common failure mode in this app's lineage is infrastructure that *looks* like it works but silently doesn't (a tap that fires but a paste that's blocked; a bundle that signs but has no identifier). Verify with `codesign -dv`, log inspection, and end-to-end tests in a real text field — not just "swift build succeeded."
- If you find a gap in the docs while working, flag it in `/debrief` rather than just plowing through. The docs are designed to evolve with the code.
