# Planning: Current Focus

What's actively in flight. Update this when you start or finish a milestone.

## Status

**M1 complete** (2026-05-26). The architectural skeleton is in place: Swift package, `RiverApp` with `MenuBarExtra`, `AppDelegate` constructing `RiverSession`, three stub `Capability` implementations (all return `.unknown`), `SettingsStore` with a placeholder key, and the bundle → sign → install pipeline. Build, test, install, launch, and quit all verified end-to-end with the locally signed `River Dev` identity.

## Next up

[M2: Capability layer + onboarding](milestones.md#m2-capability-layer--onboarding). Replace the `.unknown` returns in each `Capability` with real TCC checks. Wire `OnboardingView`'s per-capability rows with working `Grant` buttons (Microphone auto-prompts; Accessibility and Input Monitoring deep-link to System Settings). Run `/brief` before starting.

## Working agreement

- Before any non-trivial code change: run `/brief` to find applicable conventions.
- After any non-trivial code change: run `/debrief` to keep docs aligned.
- Commit using conventional commits (see [../conventions/git.md](../conventions/git.md)).
- Don't push to `main` directly. PRs only.

## Notes for the agent picking this up

- The architecture docs encode hard-won lessons from a predecessor implementation. Treat the **Why:** annotations seriously — they exist because someone got bitten.
- The most common failure mode in this app's lineage is infrastructure that *looks* like it works but silently doesn't (a tap that fires but a paste that's blocked; a bundle that signs but has no identifier). Verify with `codesign -dv`, log inspection, and end-to-end tests in a real text field — not just "swift build succeeded."
- If you find a gap in the docs while working, flag it in `/debrief` rather than just plowing through. The docs are designed to evolve with the code.
