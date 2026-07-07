# Planning: Transient, Actionable Error Toasts (roadmap 0018)

A queued backlog item from the 2026-07-06 UX review. Graduate cycle errors from a static menu-dropdown row into a transient, in-focus toast on the recording HUD — the "richer error surface" that [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) already reserves space for. **Depends on 0002** (the panel is the delivery surface); the two can land as one PR (see the feedback-layer grouping in [_index.md](_index.md)).

## Problem

Every cycle error today renders as one static text row *inside* the menu dropdown — the user discovers it only if they notice the warning glyph and open the menu, after the cycle has already returned to `.idle`. For errors where the user's next action is obvious and immediate — "No text field focused — click into a text field and try again", a paste failure, an empty transcription — the feedback should appear where the user is already looking (the same visual-focus argument as 0002), then get out of the way.

## Design: one redacted error, two renderers, structured presentation

- **Structure the presentation, not the error.** The typed `FreeFlowError` taxonomy (`.audioCapture` / `.transcription` / `.textInsertion`) already exists and is not changing. Add a **pure mapping** (like `MenuBarPresentation.visual`) from error kind → presentation: user-facing headline, recovery hint, and transience (auto-clear duration vs. lingering).
- **Two renderers of the same redacted value**, per 0002's "Relationship to the error surface": the **menu row stays** as the lingering, glanceable record; the **HUD toast** is the momentary in-focus alert. Different roles, not duplication.
- **Redaction stays exactly once** at the `AppState.apply(_:)` choke point ([ADR 0002](../decisions/0002-log-redaction-over-debug-flag.md)); both renderers consume the already-redacted value. No new path for user content into logs (anti-pattern #4).
- **Auto-clear extends the existing lifecycle rules** ("fresh `.recording` clears the error") with a timed dismiss for the toast; the timer uses an injectable clock, same pattern as `TapStateMachine`.

## Acceptance criteria

1. A cycle error produces a transient toast in the HUD panel with a headline and recovery hint, auto-dismissing after a bounded duration.
2. The menu-dropdown error row behaves exactly as today (lingering record; warning glyph overrides only the idle icon).
3. The error-kind → presentation mapping is a pure, unit-tested function covering every `FreeFlowError` case.
4. `AppState` lifecycle tests cover: set, timed auto-clear (injectable clock), clear-on-new-recording, and the existing path-redaction regression tests stay green.
5. The toast, like the HUD it rides, never takes key focus (0002 acceptance criterion 3 extends to the error variant).

## What it does not do

- Does not change `FreeFlowError` or the session's error publisher — presentation layer only.
- Does not add notifications, alerts, or any surface beyond the menu row + HUD toast.
- Does not touch redaction placement (single choke point preserved).

## Related

- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) — the delivery surface; §"Relationship to the error surface" is this spec's seed
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the error seam and clearing rules this extends
- [../decisions/0002-log-redaction-over-debug-flag.md](../decisions/0002-log-redaction-over-debug-flag.md) — redact-once at the `AppState` boundary
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — #4 (no user content in logs; redacted error strings)
