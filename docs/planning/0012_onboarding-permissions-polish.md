# Planning: Onboarding & Permissions UX Polish (roadmap 0012)

Two related rough edges in the first-run permissions flow, surfaced during the pre-v0.1.0 clean-slate validation. **Neither blocks V1** — getting the app working is low-friction and the relaunch path is reliable — but both make the grant experience feel buggier than it is. They share a root theme: **macOS doesn't reflect a just-granted permission to an already-running process, and the app's in-session re-check is best-effort.** Pre-existing (shipped at M7); not introduced by any recent change.

## 1. A freshly-granted Accessibility permission doesn't reflect until repeated Refresh

**Observed:** Accessibility toggled on in System Settings, but the onboarding row stayed "not granted" until "Refresh permission status" was clicked several times.

**Why.** `AccessibilityCapability.recheck()` calls `AXIsProcessTrusted()`; if true, it runs the silent-no-op `probe()` (synthesize a Shift modifier, then *immediately* read `CGEventSource.flagsState`). Two transient failures are possible right after the grant:
- **TCC propagation lag** — `AXIsProcessTrusted()` often doesn't flip to `true` for an already-running process until a relaunch.
- **The probe races itself** — it reads the synthesized modifier with no settle time; if the event hasn't propagated yet, the probe reports "not delivered" and `recheck()` **downgrades to `.denied`**, so the row shows "not granted" even though the OS has it on. Repeated Refresh "eventually" works by catching a moment when timing aligns.

The reliable path today is the relaunch the onboarding copy already prescribes.

**Proposed fix.** On a probe failure that occurs *right after* `AXIsProcessTrusted()` reports trusted, **retry the probe once or twice with a short settle delay before downgrading**, and consider surfacing "couldn't confirm" (`.unknown`) rather than "not granted" (`.denied`) on a transient failure. Must **preserve the genuine silent-no-op detection** ([anti-patterns.md](../conventions/anti-patterns.md) #3): a *persistent* failure still downgrades to `.denied`; only the just-granted transient is forgiven.

## 2. No on-demand way to re-open onboarding

**Observed:** after granting one permission (e.g. Input Monitoring, which macOS requires a quit+relaunch for) the flow feels awkward with the others still pending, and there's no obvious way to re-summon the permissions view without relaunching.

**Current behavior (works, but only via relaunch).** `OnboardingCoordinator.presentIfNeeded()` re-opens onboarding on every launch if any capability isn't `.granted`, and a `.granted → !.granted` degradation also re-presents it. Since Input Monitoring/Accessibility grants need a relaunch anyway, the relaunch re-gates onboarding for the remaining permissions. The gap is purely **in-session, on-demand** re-opening — the menu bar has only Settings/Quit, and `SettingsView` has no permissions section, so a user who closes the onboarding window early relies on relaunch.

**Proposed fix.** Add a **"Permissions…" menu-bar item** (and/or a permissions section in `SettingsView`) that re-presents the permissions view on demand — `OnboardingCoordinator` already owns the present logic; it needs a menu entry wired to it (likely a `forcePresent()` that shows even when all are granted, with an "all set" state).

## 3. (Optional) Clearer relaunch copy

Both grants effectively require a relaunch to take effect — Input Monitoring *always* (the event tap is created at startup). The onboarding copy mentions it ("if it still shows Not granted, quit and relaunch"), but undersells it. Consider stating relaunch as the expected finalizer, not a fallback.

## Acceptance criteria

1. Toggling Accessibility on reflects as "granted" on the first Refresh (or after the prescribed relaunch) without repeated clicks — **and** a genuinely silent-no-op bundle still downgrades to denied.
2. The user can re-open the permissions view at any time from the menu bar, without relaunching.
3. Relaunch guidance reads as the expected step, not a last resort.

## Related

- [../architecture/capabilities.md](../architecture/capabilities.md) — `recheck()` and the silent-no-op `probe()` this tunes
- [../architecture/permissions.md](../architecture/permissions.md) — the TCC grant story and why some grants need a relaunch
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the menu bar, where a "Permissions…" item would live
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — #3 (silent-no-op), which the probe must keep detecting
