# Planning: Cancel Recording (roadmap 0017)

A queued backlog item from the 2026-07-06 UX review. Give the user a way to discard an in-flight recording — today the state machine has no discard path, so every recording runs to transcription and paste.

> **Amended by [0025](0025_streaming-dictation.md) (2026-07-11):** under streaming dictation, "no transcription, no paste" cannot hold once segments have already been inserted — cancel becomes *discard the un-pasted tail*; already-inserted text stays. This spec's semantics are unchanged for the one-shot mode.

## Problem

Once `.recording`, the cycle always proceeds: `.recording → .processing → .idle`, transcribing and pasting whatever was captured. An accidental activation (brushed the hotkey, changed your mind mid-sentence) costs the user a full transcription wait *plus* deleting unwanted text out of their document. There is no escape hatch — a dead-end state the UX review flagged.

## Design: a discard transition on the session

- **New transition `.recording → .idle` (cancel):** stop audio capture, **discard** the buffers, skip transcription and paste entirely, return to `.idle`. Emit a notice (the existing `notices` channel → menu dropdown, and the HUD once [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) lands) so the cancel is visible, not silent.
- `FreeFlowSession` stays the **single state writer**; the cancel is one more guarded transition (`guard state == .recording`), so the existing re-entrancy posture extends naturally.
- **Pending deferred reconfigurations still apply** on the return to `.idle` — the cancel path must run the same deferral loop as the normal cycle end (see [../architecture/free-flow-session.md](../architecture/free-flow-session.md)).
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

## Related

- [../architecture/free-flow-session.md](../architecture/free-flow-session.md) — the state machine and deferral loop this extends
- [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md) — the `.listenOnly` / `.flagsChanged`-only posture the trigger choice must respect
- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — the tap thread any filtering runs on
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — #7 (no mid-cycle tap teardown)
