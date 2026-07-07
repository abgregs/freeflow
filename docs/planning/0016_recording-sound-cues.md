# Planning: Audible Recording Cues (roadmap 0016)

A queued backlog item from the 2026-07-06 UX review. Play a short system sound when a recording starts and when it stops, behind a Settings toggle — the audio sibling of the visual feedback layer (see the feedback-layer grouping in [_index.md](_index.md)).

## Problem

Today the *only* in-cycle feedback is the menu-bar icon — out of the user's visual focus during dictation (their eyes are on the text field; the same gap that motivates [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md)). There is no sound, no haptic, nothing that confirms "recording actually started" without hunting the menu bar. An audible cue works even when the HUD would be missed (screen shared, full-screen video, user looking at the keyboard) and matches the affordance macOS built-in dictation users already know.

## Design

- **`Settings.playFeedbackSounds`** (`Bool`) — a real `SettingKey` in `SettingsStore` from day 1 with a toggle in `SettingsView`, per [../architecture/configuration.md](../architecture/configuration.md) and anti-pattern #1 (no compile-time constants for user-facing behavior). Default: decide during implementation (macOS dictation defaults to on).
- **A small observer of the state seam** (e.g. `SoundFeedbackController`) — subscribes to the same `FreeFlowState` publisher the menu bar renders ([../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)):
  - `.idle → .recording` → begin cue
  - `.recording → .processing` → end cue
  - (Optional, decide during implementation: a distinct cue on cycle error, composing with [0018_transient-error-toasts.md](0018_transient-error-toasts.md).)
- **Mode-agnostic by construction**, same as the HUD: the controller observes state, not the activation mode, so Hold / Single Tap / Double Tap produce identical cues.
- **Playback via `NSSound`/system sounds** — no capability-owned OS surface is involved, so the one-call-site rules (load-bearing rule #3) are untouched.

## Caution: cue bleed into the capture

The begin cue plays while (or just before) the microphone starts capturing, so the cue can bleed into the recorded audio. macOS dictation accepts this trade-off. Mitigations to weigh during implementation: a short/quiet cue, or ordering the cue just before `startRecording` so most of it lands pre-capture. Not a blocker — Whisper is robust to a brief leading chirp — but verify on-device that transcription quality is unaffected.

## Acceptance criteria

1. With the toggle on, a begin cue plays on recording start and an end cue on recording stop — identical across Hold / Single Tap / Double Tap.
2. With the toggle off, no sound ever plays.
3. The state-transition → cue mapping is unit-tested against a fake player (which cue, how many times, honoring the setting); the audible leaf is manual, like other OS-call leaves ([../conventions/tests.md](../conventions/tests.md)).
4. The setting round-trips through `SettingsStore` (key declared once, anti-pattern #8).

## Related

- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) — the visual sibling; both are additional observers of the same state seam
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the seam this subscribes to
- [../architecture/configuration.md](../architecture/configuration.md) — where the new setting slots in
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — #1 (settings live in `SettingsStore` from day 1), #8 (single key declaration)
