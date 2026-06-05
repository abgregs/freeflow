# Planning: Recording Indicator HUD (roadmap 0002)

A queued roadmap item — **deferred but captured**. A floating, fixed-position, non-activating status indicator (a "toast") that shows `.recording` / `.processing` where the user's attention actually is, fading out on `.idle`. Depends on the state seam introduced by the **Menu-bar visual state** milestone; orderable independently of [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md) (both are post-menu-bar feature inserts). See [_index.md](_index.md) for the `NNNN_` ordering convention.

## Why a HUD in addition to the menu-bar icon

`requirements/core-feature.md` item 5 puts state in the menu-bar icon — glanceable, but *out of the user's visual focus during dictation* (their eyes are on the text field). For a hold-to-talk app, a floating indicator in a consistent on-screen spot gives immediate "I'm recording / processing" feedback without the user hunting the menu bar.

**Mode-agnostic by construction.** The indicator reflects `FreeFlowState`, never the activation mode — so Hold, Single Tap, and Double Tap produce an identical "currently recording" indication. **Why structural:** the state machine sits downstream of `HotkeyManager`'s mode interpretation; a renderer that observes state cannot see the mode.

## Design: a fixed-position, non-activating panel

- **Borderless `NSPanel`**: `.nonactivatingPanel`, `canBecomeKey = false`, floating/status window level, `ignoresMouseEvents = true`, `collectionBehavior` set to show across spaces and over full-screen apps. Hosts a SwiftUI view via `NSHostingView` — the same approach `OnboardingCoordinator` uses for its window.
- **Load-bearing constraint — must never become key or steal focus.** It appears *during* recording; if it activates, it pulls focus off the text field and breaks the paste. Enforced structurally by the panel flags plus never calling `makeKey`/`activate`. This is the recording-time analogue of [0001](0001_focused-element-paste-guard.md)'s "don't disturb the focused target."
- **Fixed screen position, not caret-anchored** (e.g. bottom-center of the active screen). See feasibility below.
- **Lifecycle = another observer of the shared state seam** (the `AppState` from the menu-bar milestone):
  - `.recording` → fade in; bouncing "…" dots / pulsing mic.
  - `.processing` → processing variant (dots morph to a spinner, or a "Transcribing…" label).
  - `.idle` → fade out, then order out. The fade must outlive the state change (animate-then-remove).
- **Ownership:** a coordinator paralleling `OnboardingCoordinator` (e.g. `RecordingIndicatorCoordinator`) that subscribes to the state seam and owns the panel lifetime — keeps `AppDelegate` a thin shell, reusing the established window-owning-coordinator pattern.

## Feasibility / maintainability analysis

- **Fixed toast vs. caret-following:** caret-following needs `kAXFocusedUIElementAttribute` → caret bounds per app (the same web/Electron/terminal brittleness flagged in 0001) plus continuous tracking. Fixed-position has **no AX dependency**, far less code, and behaves identically everywhere. **Choose fixed.**
- **Non-activating-panel correctness:** the one real risk is focus-stealing, mitigated structurally by the panel flags. Verifiable only on-device ("did Safari keep focus?") — manual check, same posture as the paste/insertion paths.
- **Pattern reuse:** `OnboardingCoordinator` already owns a window + a publisher subscription. The HUD is the same shape, so it's low-novelty to build and maintain.
- **Testability:** the `FreeFlowState → visual variant` mapping is a pure function, unit-tested like the menu-bar renderer's mapping; panel/animation/focus behavior is manual.
- **Conclusion:** a fixed-position non-activating panel driven by the shared state seam is the lowest-complexity, lowest-risk option.

## Relationship to the error surface

The Menu-bar visual state milestone ships a minimal, path-redacted error *row* in the menu (a persistent, glanceable record). This panel is the natural home for a richer, transient **error toast** ("Paste failed — check Accessibility") — a *second* renderer of the same redacted error. Menu row = lingering record; toast = momentary alert (not duplication, different roles). Any error text shown here passes through `LogRedaction.redactUserPaths` ([ADR 0002](../decisions/0002-log-redaction-over-debug-flag.md)).

## Acceptance criteria

1. While `.recording`, a floating indicator is visible in a consistent on-screen area with a bounce/pulse animation — identical across Hold / Single Tap / Double Tap.
2. It shows a processing variant on `.processing` and fades out on `.idle`.
3. It **never** takes key focus: triggering it while dictating into any app does not move focus off the target field (paste still lands). Verified on-device.
4. It appears over full-screen apps and across spaces.
5. The `FreeFlowState → variant` mapping is a pure function with unit tests; panel/focus behavior is covered by a documented manual check.

## What it does not do

- Does not track or anchor to the text caret (fixed position only).
- Does not become key / activate / steal focus.
- Does not replace the menu-bar renderer (core-feature.md item 5) — it's an additional observer of the same state.
- Does not change `FreeFlowState` or the cycle; it is read-only on the state seam.

## Decisions to make during implementation

- Exact placement and multi-display handling (active screen vs. main).
- Processing visual (morph dots → spinner vs. swap label).
- Fade timing, and whether a minimum on-screen duration prevents flicker on very short taps.
- Whether to graduate the error toast into this panel in this milestone or a later pass.

## Related

- [milestones.md](milestones.md) / [_index.md](_index.md) — the roadmap that points here
- [../requirements/core-feature.md](../requirements/core-feature.md) — item 5, the menu-bar sibling renderer
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — the state machine this observes; the error surface
- [../architecture/capabilities.md](../architecture/capabilities.md) — `OnboardingCoordinator`, the window-owning-coordinator pattern this mirrors
- [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md) — shares the "don't disturb the focused field" theme and the error-surface reuse
