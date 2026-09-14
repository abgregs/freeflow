# Planning: Cancel Recording (roadmap 0017)

A queued backlog item from the 2026-07-06 UX review. Give the user a way to discard an in-flight recording — today the state machine has no discard path, so every recording runs to transcription and paste.

## Problem

Once `.recording`, the cycle always proceeds: `.recording → .processing → .idle`, transcribing and pasting whatever was captured. An accidental activation (brushed the hotkey, changed your mind mid-sentence) costs the user a full transcription wait *plus* deleting unwanted text out of their document. There is no escape hatch — a dead-end state the UX review flagged.

## Design: a discard transition on the session

- **New transition `.recording → .idle` (cancel):** stop audio capture, **discard** the buffers, skip transcription and paste entirely, return to `.idle`. Emit a notice (the existing `notices` channel → menu dropdown, and the HUD once [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) lands) so the cancel is visible, not silent.
- `RiverSession` stays the **single state writer**; the cancel is one more guarded transition (`guard state == .recording`), so the existing re-entrancy posture extends naturally.
- **Pending deferred reconfigurations still apply** on the return to `.idle` — the cancel path must run the same deferral loop as the normal cycle end (see [../architecture/river-session.md](../architecture/river-session.md)).
- Cancel during `.processing` is **out of scope** (transcription already in flight; the paste is imminent). Ignore it, like activation-during-processing is ignored today.

## The trigger — a real design tension

The natural gesture is **Esc while recording**, but Esc is a `keyDown`, and the event tap deliberately observes **only `.flagsChanged`** with `.listenOnly` (the 0006 least-privilege hardening — see [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md)). The tap's event mask is fixed at creation, so watching Esc means observing **all keystrokes at all times** — a genuine privacy-posture regression, not just a code change. Options, to decide during implementation:

1. **Widen the mask to include `keyDown`**, filter to Esc in the callback. Simple UX; weighs directly against 0006's least-privilege rationale and changes what the Input Monitoring grant is used for.
2. **Menu-bar "Cancel Recording" item only.** Zero new event surface, but requires mousing to the menu bar mid-dictation — weak as the only path.
3. **A modifier-based gesture** on the already-watched `.flagsChanged` stream (e.g. tapping a designated *other* modifier while recording). Keeps the privacy posture and the mask unchanged; slightly less discoverable.

Option 3 (possibly plus the menu item as a discoverable fallback) preserves the security posture with no tap changes; option 1 should not be taken without explicitly revisiting the 0006 decision. Whatever is chosen: **no second `CGEvent.tapCreate` and no tap recreation** (load-bearing rule #3, anti-pattern #7).

## Acceptance criteria

1. The cancel gesture during `.recording` returns to `.idle` with **no transcription and no paste**, and a visible "canceled" notice.
2. Cancel while `.idle` or `.processing` is a no-op (logged, no state change).
3. A key/mode change deferred during the canceled recording still applies on the return to `.idle`.
4. Session transitions are unit-tested (cancel-from-recording, no-op states, deferral interaction); the gesture interpretation is unit-tested in `HotkeyManager`/`TapStateMachine` per the chosen trigger.
5. The event tap's privacy posture is explicitly recorded: either unchanged (options 2/3) or the mask widening is documented as a revision of the 0006 decision.

## Known issue, deliberately deferred: the canceled notice bleeds into the next recording

**Observed on-device 2026-09-11, in all three activation modes** (Hold, Single Tap, Double Tap). After canceling a recording, the *next* recording displays "Recording canceled." in the HUD — alongside the live level meter, while the user is actively speaking into a perfectly healthy new recording. Confusing: the message describes the previous cycle but appears to describe the current one.

**Root cause.** `AppState.apply(_ newState:)` treats the three user-facing surfaces inconsistently:

```swift
if newState == .recording {
    errorMessage = nil
    toast = nil          // cleared when a recording STARTS
}
if newState != .recording {
    notice = nil         // cleared only when a recording ENDS
}
```

`notice` is the only one not cleared on entering `.recording`. That was correct before this spec: a recording-context notice was always *set* during `.recording`, so clearing it on end was sufficient. This spec breaks that invariant deliberately — `handleCancel` emits its notice **after** the `.idle` transition, precisely so the clear-on-end rule doesn't wipe it before the user reads it. That ordering is load-bearing and correct, but it makes `notice` the first notice that can outlive a recording, and nothing then clears it when the next one begins.

**Fix when taken:** add `notice = nil` to the `newState == .recording` branch, mirroring `errorMessage`. One line, plus a test asserting a notice set while `.idle` does not survive into the next `.recording`.

**Why deferred** (maintainer decision, 2026-09-11): purely cosmetic — the new recording captures, transcribes, and pastes normally; only the stale copy is wrong. It is grouped with the other deferred HUD-polish items and will be picked up after the project rename and the UI/identity pass, since notice lifecycle and HUD copy are both in scope for that work. Deferring a one-line fix is a deliberate batching choice, not an oversight.

## Related

- [../architecture/river-session.md](../architecture/river-session.md) — the state machine and deferral loop this extends
- [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md) — the `.listenOnly` / `.flagsChanged`-only posture the trigger choice must respect
- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — the tap thread any filtering runs on
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — #7 (no mid-cycle tap teardown)
