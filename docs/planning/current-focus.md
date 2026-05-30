# Planning: Current Focus

What's actively in flight. Update this when you start or finish a milestone.

## Status

**M2 complete** (2026-05-29). The capability layer is real and onboarding works end-to-end. Each `Capability` reports honest `.granted`/`.denied`/`.unknown` from non-prompting status APIs (Microphone `AVCaptureDevice.authorizationStatus`, Accessibility `AXIsProcessTrusted()`, Input Monitoring `IOHIDCheckAccess` tri-state). `OnboardingView` iterates `[any Capability]` with working Grant/Refresh/Skip; the launch gate is `OnboardingGate.shouldPresent(for:)` ("any capability not granted"). New: `OnboardingGate`, `SystemSettingsPane`; the `Capability` protocol gained `setupInstructions` + `requestGrant()`. Verified: build + 18 tests green, and the full grant flow confirmed manually on a signed `/Applications` install.

**M1 complete** (2026-05-26). Architectural skeleton (Swift package, `MenuBarExtra`, `FreeFlowSession`/`Capability`/`SettingsStore` stubs) plus the bundle → sign → install pipeline, verified end-to-end with the `Free Flow Dev` identity.

## Next up

[M3: FreeFlowSession skeleton](milestones.md#m3-freeflowsession-skeleton). Make `FreeFlowSession` own the `FreeFlowState` machine explicitly, hold the (still-stub) managers, and subscribe to `SettingsStore` publishers (even though real keys don't land until M8); shrink `AppDelegate` toward construct-and-start. Much of the scaffold already exists from M1. Run `/brief` before starting.

## Working agreement

- Before any non-trivial code change: run `/brief` to find applicable conventions.
- After any non-trivial code change: run `/debrief` to keep docs aligned.
- Commit using conventional commits (see [../conventions/git.md](../conventions/git.md)).
- Don't push to `main` directly. PRs only.

## Notes for the agent picking this up

- The architecture docs encode hard-won lessons from a predecessor implementation. Treat the **Why:** annotations seriously — they exist because someone got bitten.
- The most common failure mode in this app's lineage is infrastructure that *looks* like it works but silently doesn't (a tap that fires but a paste that's blocked; a bundle that signs but has no identifier). Verify with `codesign -dv`, log inspection, and end-to-end tests in a real text field — not just "swift build succeeded."
- If you find a gap in the docs while working, flag it in `/debrief` rather than just plowing through. The docs are designed to evolve with the code.
