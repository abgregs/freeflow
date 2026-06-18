# Planning: Focused-element Paste Guard (roadmap 0001)

**Landed 2026-06-10** — see [current-focus.md](current-focus.md) for the as-built summary; this spec is retained as the record. Guards the synthesized paste against firing into a target that can't accept it. The `0001_` prefix orders it in the roadmap; see [_index.md](_index.md).

> **Note (2026-06-18):** [0011](0011_keystroke-injection.md) replaced clipboard + ⌘V insertion with Unicode keystroke injection. The guard described here **survives** (now the "insertion guard" — it still skips non-editable targets); only the gated insertion mechanism changed, so references below to "the clipboard + ⌘V paste" now mean keystroke injection.

## Problem

Today's paste path posts ⌘V system-wide via `.cghidEventTap` to whatever holds keyboard focus. It never targets or verifies a destination — that's the deliberate "No AX-API path" decision in [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md). The cost is that **a paste into a non-editable focused target is indistinguishable from a successful paste**: `AccessibilityCapability.postKeyEvent` doesn't throw, `FreeFlowSession.handleDeactivate` logs success, the clipboard is restored — and the transcription silently goes nowhere, or triggers an unintended app command.

The motivating case: copy something in browser dev tools, leave a DOM node selected (focus is in the inspector, not an editable field), hold the hotkey, dictate. The ⌘V lands in dev tools, which does whatever it does with ⌘V-on-a-selection. No error surfaces. **Why this matters:** it's the silent-failure lineage this project exists to make structurally impossible (see [../conventions/anti-patterns.md](../conventions/anti-patterns.md)) — a paste that "looks like it worked but didn't."

Secondary: the first `postKeyEvent` after `.granted` runs `probe()`, which injects a stray (invisible) Shift keystroke into the focused app before the ⌘V. Worth suppressing on the non-editable path as related cleanup.

## Mechanism: a read-only focused-element role check

Before posting ⌘V, read the system-wide focused UI element and its AX role; proceed only if it's a text-bearing role, otherwise skip the paste and surface a "no text field focused" signal. APIs: `AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute` → `kAXRoleAttribute` (and subrole).

**This is read-only AX, not the AX write path that "No AX-API path" rejected.** That decision rejected AX *writes* (setting a field's value) as brittle across browsers, Electron, and terminals. A role *read* is cheap and only gates whether we attempt the existing clipboard + ⌘V paste — it never becomes the insertion mechanism. **Coordination note (executed at landing):** the "No AX-API path" section of [`free-flow-pipeline.md`](../architecture/free-flow-pipeline.md) now records this read-only exception, so the doc doesn't read as "zero AX calls" when there's now one.

## Editable-role taxonomy

- **Native:** `AXTextField`, `AXTextArea`, `AXComboBox`, secure text field, search field (subrole `AXSearchField`).
- **Web / Electron:** the focused element often surfaces as `AXTextField` / `AXTextArea`, or as a web area (`AXWebArea`) whose content is `contenteditable`. Reporting is inconsistent across apps.
- **Terminals:** Terminal / iTerm may report `AXTextArea` or a custom role.

Maintain an allowlist of editable roles. The classification logic is the unit-testable core; the OS call is the untestable leaf.

## Fail open on ambiguity

AX role reporting in web and Electron content is unreliable — `contenteditable` may not present a standard editable role, and some apps under-report. **The guard must fail OPEN when the role can't be determined:** default to attempting the paste (today's behavior) rather than blocking. **Why:** failing closed would regress working dictation in apps with poor AX exposure; failing open preserves current behavior and only adds a signal for the *clearly* non-editable case (a selected DOM node, a focused button, a list-row selection). The guard catches the obvious miss; it is not a strict gatekeeper.

## User-facing surface

When the guard skips, it shows "No text field focused" via the menu-bar label / session-level error publisher rather than doing nothing visibly. That surface was built by the **Menu-bar visual-state** milestone (the `FreeFlowSession.errors` publisher + the `AppState` bridge, now landed — see [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)). Reusing it, instead of inventing a one-off signal here, is the reason this milestone is sequenced after it.

## Acceptance criteria

1. Dictating with a clearly non-editable target focused (a dev-tools DOM selection, a focused button) posts **no** ⌘V; the user gets a visible "no text field focused" signal; the clipboard is untouched.
2. Dictating into a standard editable field (Notes, TextEdit, a browser text input, a search field) pastes exactly as today — no regression.
3. An ambiguous / undeterminable AX role fails open (attempts the paste) and logs the case so it's observable.
4. The role-classification logic is unit-tested against a table of roles (editable / not / unknown) with no real AX grant required. The OS-call leaf is isolated behind an internal seam, mirroring `AccessibilityCapability.probe()`.
5. No new `CGEvent.post` call site (load-bearing rule #3): the guard sits in front of the existing `postKeyEvent`.

## What this milestone does not do

- Does not introduce an AX *write* path — text is still inserted via clipboard + ⌘V.
- Does not verify the paste *succeeded* after the fact (no post-paste value diff — too racy).
- Does not try to be correct for every web / Electron app; it fails open on ambiguity.

## Decisions to make during implementation

- **Where the check lives:** leaning `AccessibilityCapability` (it owns AX and the single `CGEvent.post` site, keeping "one source of truth for OS API calls"), versus `TextInsertionManager`.
- The exact editable-role allowlist, and whether to consult subroles.
- Whether to suppress the first-use Shift `probe()` keystroke when the target is non-editable.

## Related

- [milestones.md](milestones.md) — the ordered roadmap that points here
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — "No AX-API path", the decision this read-only check refines
- [../requirements/core-feature.md](../requirements/core-feature.md) — item 4 (text appears at cursor) and item 5 (visible feedback, the surface this reuses)
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — the silent-failure lineage this guard closes
