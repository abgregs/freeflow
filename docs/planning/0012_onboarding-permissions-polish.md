# Planning: Onboarding & Permissions UX Polish (roadmap 0012)

Two related rough edges in the first-run permissions flow, surfaced during the pre-v0.1.0 clean-slate validation. **Neither blocks V1** — getting the app working is low-friction and the relaunch path is reliable — but both make the grant experience feel buggier than it is. They share a root theme: **macOS doesn't reflect a just-granted permission to an already-running process, and the app's in-session re-check is best-effort.** Pre-existing (shipped at M7); not introduced by any recent change.

## 1. A freshly-granted Accessibility permission doesn't reflect until repeated Refresh

**Observed:** Accessibility toggled on in System Settings, but the onboarding row stayed "not granted" until "Refresh permission status" was clicked several times.

**Why.** `AccessibilityCapability.recheck()` calls `AXIsProcessTrusted()`; if true, it runs the silent-no-op `probe()` (synthesize a Shift modifier, then *immediately* read `CGEventSource.flagsState`). Two transient failures are possible right after the grant:
- **TCC propagation lag** — `AXIsProcessTrusted()` often doesn't flip to `true` for an already-running process until a relaunch.
- **The probe races itself** — it reads the synthesized modifier with no settle time; if the event hasn't propagated yet, the probe reports "not delivered" and `recheck()` **downgrades to `.denied`**, so the row shows "not granted" even though the OS has it on. Repeated Refresh "eventually" works by catching a moment when timing aligns.

The reliable path today is the relaunch the onboarding copy already prescribes.

**Proposed fix.** On a probe failure that occurs *right after* `AXIsProcessTrusted()` reports trusted, **retry the probe once or twice with a short settle delay before downgrading**, and consider surfacing "couldn't confirm" (`.unknown`) rather than "not granted" (`.denied`) on a transient failure. Must **preserve the genuine silent-no-op detection** ([anti-patterns.md](../conventions/anti-patterns.md) #3): a *persistent* failure still downgrades to `.denied`; only the just-granted transient is forgiven.

**Field addendum (2026-08-19):** the same false-negative shape appears on every *first launch of a freshly rebuilt binary* — status reads denied at launch, and a Grant-roundtrip + Refresh flips it green with no TCC changes (the pane row was valid throughout; see [../architecture/distribution.md](../architecture/distribution.md)). The implementation should instrument whether `AXIsProcessTrusted()` or the probe is the false-negative source; either way, the settle-retry (plus item 4's post-Grant auto-recheck) is what turns dev rebuilds — and any user's stale-status launch — into a zero-touch experience.

## 2. No on-demand way to re-open onboarding

**Observed:** after granting one permission (e.g. Input Monitoring, which macOS requires a quit+relaunch for) the flow feels awkward with the others still pending, and there's no obvious way to re-summon the permissions view without relaunching.

**Current behavior (works, but only via relaunch).** `OnboardingCoordinator.presentIfNeeded()` re-opens onboarding on every launch if any capability isn't `.granted`, and a `.granted → !.granted` degradation also re-presents it. Since Input Monitoring/Accessibility grants need a relaunch anyway, the relaunch re-gates onboarding for the remaining permissions. The gap is purely **in-session, on-demand** re-opening — the menu bar has only Settings/Quit, and `SettingsView` has no permissions section, so a user who closes the onboarding window early relies on relaunch.

**Proposed fix.** Add a **"Permissions…" menu-bar item** (and/or a permissions section in `SettingsView`) that re-presents the permissions view on demand — `OnboardingCoordinator` already owns the present logic; it needs a menu entry wired to it (likely a `forcePresent()` that shows even when all are granted, with an "all set" state).

## 3. (Optional) Clearer relaunch copy

Both grants effectively require a relaunch to take effect — Input Monitoring *always* (the event tap is created at startup). The onboarding copy mentions it ("if it still shows Not granted, quit and relaunch"), but undersells it. Consider stating relaunch as the expected finalizer, not a fallback.

## 4. Field flow (2026-08-18): the stale-row dead end — added from the 0004/0021/0002 on-device smoke

The exact observed loop on a dev rebuild (and reproducible for any user whose Accessibility row goes stale):

1. Launch → onboarding shows 2 granted, Accessibility "not granted."
2. User clicks **Grant** → System Settings opens — and shows River *already toggled on*. Two very different causes produce this identical view, and the user can't tell them apart: a **stale row** bound to a previous binary (tccd does not authorize the running one; toggling it fixes nothing — it must be removed and re-added), or a **fresh valid row** where the grant genuinely took and only the app's displayed status is behind. Either way the user reasonably wonders whether Grant did anything at all.
3. Meanwhile the onboarding window is easy to lose — Settings opens over it (often on another Space/screen) and nothing re-fronts or tracks it, so the user has to go hunt for it. Not a dismissal bug; a discoverability gap in the flow.
4. In the stale-row case, "Refresh permission status" changes nothing — correctly, since the process genuinely isn't authorized — but offers no recourse or explanation. In the valid-row case (verified 2026-08-18 after a clean delete + reinstall), Refresh **does** flip the row green — but only if the user knows to go back and press it; nothing in the flow says so.
5. A user who instead just closes Settings and starts dictating is accepted into a recording that can only die at paste time — see the gate below. And in the stale-row case, the actual fix (remove the row with **−**, re-add fresh) is documented nowhere in the product.

Root cause and the durable fix, field-verified: rows created by tccd via a request API survive rebuilds (Microphone's native prompt row did); pane-added rows don't — and Accessibility can *only* be pane-added today because the app never calls the prompting APIs. See [../architecture/distribution.md](../architecture/distribution.md) "Permissions across installs and rebuilds."

**Proposed fixes (extending items 1–3):**

- **Call the request APIs.** `AXIsProcessTrustedWithOptions([prompt: true])` for Accessibility and `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` for Input Monitoring, from the onboarding Grant action — tccd then creates and owns the row against the stable signing identity, the OS dialog deep-links the user correctly, and the stale-row trap can't form.
- **The onboarding window re-fronts after the Grant round-trip.** It never actually closes, but Settings buries it; re-fronting it when the user returns (or on a status change) keeps the status view and the Refresh affordance in hand — and a post-Grant auto-recheck would remove the need to know about Refresh at all.
- **Stale-row guidance.** When a Refresh after a Grant round-trip still reads denied, onboarding should say the quiet part: "If River already appears enabled in System Settings, remove it with − and add it again" — the only working recovery until the row is tccd-owned.
- **Pre-recording capability gate.** `handleActivate` currently gates on model-readiness but not on capability status: the app logged Accessibility as denied, re-opened onboarding, *and still accepted a 35-second dictation* that could only die at paste time. A known-denied capability must decline activation up front (the 0004 gate pattern: decline + error toast), so the user's speech is never accepted into a doomed cycle.

## 5. Design principle (2026-09-14): permission status is the app's job, not the user's

**Recorded during the #33 smoke; deferred with ACs 3, 4, and 6.**

Every rebuild smoke in the #30–#33 review cycle produced the same sequence: launch, onboarding appears showing Accessibility "not granted," the user presses **Refresh**, it flips green. Every time.

That Refresh press has no downside and no judgment in it. Its only trigger is the user seeing a status the app could have determined itself. It is a deterministic check performed by hand. Friction the app imposes on the user for its own bookkeeping.

**The friction is designed in, in three specific places:**

1. **The launch gate trusts a single read.** `OnboardingCoordinator.presentIfNeeded()` decides from `OnboardingGate.shouldPresent(for:)` against one launch-time status read, which on a rebuilt binary is a known false negative (see section 1's field addendum). So onboarding is shown to a user who already granted everything.
2. **The happy-path transition is explicitly delegated to a click.** The coordinator's status hook handles only `.granted → !.granted`, and its comment states the other direction outright: *"A `.denied → .granted` transition is handled by the user re-clicking Refresh in the onboarding view itself, not by this coordinator."*
3. **Nothing rechecks when the user comes back, and nothing dismisses.** There is no recheck on app activation — the moment a user returns from System Settings — and no path that closes onboarding once every capability reads granted.

**Target behavior:**

- **Trigger trust re-evaluation before deciding to present.** A user whose permissions are all valid never sees onboarding. *How* is open — see below: a time-based retry is not sufficient.
- **Recheck automatically when it could have changed** — on app activation and on onboarding window focus, which is exactly when a user returns from granting.
- **Dismiss onboarding the moment every capability reads granted**, so the user goes straight to dictating.
- **The Refresh button becomes redundant.** Decide during implementation whether to remove it or keep it as a demoted fallback; either way it must stop being a required step.

**Which read is actually wrong — corrected by the #33 smoke (2026-09-14).** There are two status reads, and #33's retry only covers one. At launch, `init()` reads `AXIsProcessTrusted()` alone — no probe. On Refresh, `recheck()` reads `AXIsProcessTrusted()` and runs the probe *only if it returned trusted*; #33's retry wraps that probe. On-device, a rebuilt binary showed **no change with #33**: launch still reads not-granted, and a single Refresh flips it green, exactly as before. That places the false negative on the `AXIsProcessTrusted()` read, not on the probe — which passes first time once trust reads true, so the retry never engages in this flow.

**And the trigger is opening the pane, not time.** The maintainer isolated the one required action: open System Settings → Accessibility (via Grant), where River is *already toggled on*; touch nothing; come back; press Refresh → green. No toggle, no re-add. Opening the pane is the step that flips `AXIsProcessTrusted()` for the rebuilt binary — consistent with System Settings re-validating listed entries against current code signatures when the pane is displayed. The earlier guess that this was a probe race that settles on its own was wrong.

Consequence for the design: **no amount of rechecking or waiting removes this friction on its own**, because the trust read does not change until something makes the system re-evaluate the entry. Auto-recheck (AC8) is still right — it removes the Refresh press once re-evaluation has happened — but the pane-open step would remain. #33's retry stays a reasonable backstop for the trusted-but-probe-lags case; it is not this mechanism.

The candidate for triggering re-evaluation programmatically is **AC4's request API**, `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`, called when the launch read comes back false. That ties AC4 to the zero-touch goal, not just to stale rows. **Unverified — test on-device before designing around it:** whether it re-evaluates an existing enabled entry silently, or instead raises the system prompt, determines whether it removes friction or merely relocates it.

**What auto-recheck cannot fix:** the stale row (section 4). There, "denied" is the *correct* reading — tccd genuinely does not authorize the running binary — so no amount of rechecking helps, and AC6's recovery guidance is still required. Zero-touch removes the friction from the case where the app was simply wrong about the state; it does not replace guidance for the case where the state is genuinely broken.

## Acceptance criteria

1. Toggling Accessibility on reflects as "granted" on the first Refresh (or after the prescribed relaunch) without repeated clicks — **and** a genuinely silent-no-op bundle still downgrades to denied.
2. The user can re-open the permissions view at any time from the menu bar, without relaunching.
3. Relaunch guidance reads as the expected step, not a last resort.
4. Granting Accessibility/Input Monitoring goes through the request APIs: the row is tccd-created, survives a same-identity rebuild, and after the Grant round-trip the onboarding window is re-fronted with a fresh status check (no user-discovered Refresh required).
5. With any required capability known-denied, activation is declined with clear feedback before audio capture starts — no dictation is accepted into a cycle that cannot paste.
6. A persistent post-grant denied status surfaces the stale-row recovery guidance (remove and re-add), not a bare "not granted."
7. A user whose required capabilities are all valid never sees onboarding at launch, including on the first launch of a rebuilt binary — the gate decides only after a settled recheck.
8. No required path to a working app involves pressing Refresh: status rechecks automatically on app activation and onboarding focus, and onboarding dismisses itself once every required capability reads granted.

## Related

- [../architecture/capabilities.md](../architecture/capabilities.md) — `recheck()` and the silent-no-op `probe()` this tunes
- [../architecture/permissions.md](../architecture/permissions.md) — the TCC grant story and why some grants need a relaunch
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the menu bar, where a "Permissions…" item would live
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — #3 (silent-no-op), which the probe must keep detecting
