# Planning: Current Focus

What's actively in flight. Update this when you start or finish a milestone.

## Status

**M3 complete** (2026-06-01). `RiverSession.start` subscribes to `SettingsStore` publishers via `subscribeToConfiguration()`; `applyOrDeferReconfiguration` applies directly when idle and parks the change in `pendingReconfiguration` otherwise (structural backing for anti-pattern #7). `stop` clears the subscription set. Internal counters (`configurationApplyCount` / `configurationDeferCount`) let tests assert wiring without inspecting closures. Verified: build + 22 tests green. No user-observable change — wiring stub for M8's real keys.

**M2 complete** (2026-05-29). Capability layer real, onboarding end-to-end: honest `.granted`/`.denied`/`.unknown` from non-prompting status APIs (Microphone `AVCaptureDevice.authorizationStatus`, Accessibility `AXIsProcessTrusted()`, Input Monitoring `IOHIDCheckAccess` tri-state); `OnboardingView` iterates `[any Capability]` with Grant/Refresh/Skip; gate via `OnboardingGate.shouldPresent(for:)`. New: `OnboardingGate`, `SystemSettingsPane`; `Capability` gained `setupInstructions` + `requestGrant()`. Manually verified on a signed `/Applications` install.

**M1 complete** (2026-05-26). Architectural skeleton (Swift package, `MenuBarExtra`, `RiverSession`/`Capability`/`SettingsStore` stubs) plus the bundle → sign → install pipeline, verified end-to-end with the `River Dev` identity.

## Next up

[M4: Hotkey detection (Hold mode)](milestones.md#m4-hotkey-detection-hold-mode). `InputMonitoringCapability` gains the real `CGEventTap` on the dedicated `com.river.eventtap` background thread; `HotkeyManager` consumes the event stream and fires semantic `onActivate`/`onDeactivate` callbacks. Default key Right Control, Hold mode only. `RiverSession` transitions `.idle` ↔ `.recording` in response. The [threading invariant](../architecture/threading-invariant.md) is the central constraint. Run `/brief` before starting.

## Working agreement

- Before any non-trivial code change: run `/brief` to find applicable conventions.
- After any non-trivial code change: run `/debrief` to keep docs aligned.
- Commit using conventional commits (see [../conventions/git.md](../conventions/git.md)).
- Don't push to `main` directly. PRs only.

## Notes for the agent picking this up

- The architecture docs encode hard-won lessons from a predecessor implementation. Treat the **Why:** annotations seriously — they exist because someone got bitten.
- The most common failure mode in this app's lineage is infrastructure that *looks* like it works but silently doesn't (a tap that fires but a paste that's blocked; a bundle that signs but has no identifier). Verify with `codesign -dv`, log inspection, and end-to-end tests in a real text field — not just "swift build succeeded."
- If you find a gap in the docs while working, flag it in `/debrief` rather than just plowing through. The docs are designed to evolve with the code.
