# Planning: Current Focus

What's actively in flight. Update this when you start or finish a milestone.

## Status

**M4 complete** (2026-06-01). `InputMonitoringCapability` owns the system-wide `CGEventTap` on a dedicated `com.river.eventtap` background thread (QoS `.userInteractive`); the C tap callback decodes events and hops to the main actor via `Task { @MainActor in ... }` before publishing `TapEvent`s. `HotkeyManager` interprets `.flagsChanged` for the watched keycode (Hold mode only — tap modes land in M9) and fires semantic `onActivate`/`onDeactivate`. `RiverSession` transitions `.idle` ↔ `.recording` in response, state-guarded. Default activation key is **Right Option** (keycode 61). `Settings.m1Placeholder` removed; `Settings.activationKeyCode` is live. Tap self-heals on `.tapDisabled*`. Verified: build + 34 tests green, plus on-device end-to-end (press/release of Right Option drives the state machine, visible in `log stream`).

**M3 complete** (2026-06-01). `RiverSession.start` subscribes to `SettingsStore` publishers via `subscribeToConfiguration()`; `applyOrDeferReconfiguration` applies directly when idle and parks the change in `pendingReconfiguration` otherwise (structural backing for anti-pattern #7). `stop` clears the subscription set. Internal counters (`configurationApplyCount` / `configurationDeferCount`) let tests assert wiring without inspecting closures.

**M2 complete** (2026-05-29). Capability layer real, onboarding end-to-end: honest `.granted`/`.denied`/`.unknown` from non-prompting status APIs (Microphone `AVCaptureDevice.authorizationStatus`, Accessibility `AXIsProcessTrusted()`, Input Monitoring `IOHIDCheckAccess` tri-state); `OnboardingView` iterates `[any Capability]` with Grant/Refresh/Skip; gate via `OnboardingGate.shouldPresent(for:)`. New: `OnboardingGate`, `SystemSettingsPane`; `Capability` gained `setupInstructions` + `requestGrant()`.

**M1 complete** (2026-05-26). Architectural skeleton (Swift package, `MenuBarExtra`, `RiverSession`/`Capability`/`SettingsStore` stubs) plus the bundle → sign → install pipeline, verified end-to-end with the `River Dev` identity.

## Next up

[M5: Audio capture](milestones.md#m5-audio-capture). `MicrophoneCapability` owns audio-engine start/stop. `AudioCaptureManager` records hardware-format audio while held, handles the engine-warmup race (waits for first buffer before teardown), then converts to 16 kHz mono Float32 on stop. `RiverSession` calls into the manager during `.recording` and introduces the `.processing` state on deactivation (currently `.recording → .idle` directly). Run `/brief` before starting.

## Working agreement

- Before any non-trivial code change: run `/brief` to find applicable conventions.
- After any non-trivial code change: run `/debrief` to keep docs aligned.
- Commit using conventional commits (see [../conventions/git.md](../conventions/git.md)).
- Don't push to `main` directly. PRs only.

## Notes for the agent picking this up

- The architecture docs encode hard-won lessons from a predecessor implementation. Treat the **Why:** annotations seriously — they exist because someone got bitten.
- The most common failure mode in this app's lineage is infrastructure that *looks* like it works but silently doesn't (a tap that fires but a paste that's blocked; a bundle that signs but has no identifier). Verify with `codesign -dv`, log inspection, and end-to-end tests in a real text field — not just "swift build succeeded."
- If you find a gap in the docs while working, flag it in `/debrief` rather than just plowing through. The docs are designed to evolve with the code.
