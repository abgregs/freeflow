# Requirement: Core Feature

## User story

> As a Mac user, I press (or tap) a configurable modifier key, speak, release (or tap again), and my words appear as text wherever my cursor is focused — without my voice or text leaving my device.

## Acceptance criteria

1. **Activation works.** The configured activation key triggers recording per the selected mode (see [activation-key-and-mode.md](activation-key-and-mode.md)).
2. **Recording captures real audio.** Pressing the key (Hold mode) or completing a tap (tap modes) produces a non-empty audio buffer for any utterance ≥ ~100 ms. Recording of length 0 must not silently succeed; either capture or fail loudly.
3. **Transcription happens locally.** WhisperKit runs on-device. No network call for the transcription itself.
4. **Text appears at the cursor.** Synthesized ⌘V pastes the transcription into whatever text field currently has focus. The user's original clipboard is restored after the paste lands.
5. **Visible feedback at every state.** The menu bar icon reflects state: empty mic (`.idle`), filled mic (`.recording`), three-dot indicator (`.processing`). Opening the menu shows a matching label ("Ready" / "Recording..." / "Processing...").
6. **No data leaves the device.** Audio, transcribed text, and dictionary terms are never sent over a network by the app itself. (WhisperKit may download model files on first use — this is the only network behavior.)
7. **Settings change without restart.** Changes to the activation key or mode in Settings apply within one second, without quitting the app. See [activation-key-and-mode.md](activation-key-and-mode.md).
8. **First-launch onboarding guides the user through permissions.** See "First-launch onboarding" below.

## First-launch onboarding

On every launch the onboarding gate checks every [Capability](../architecture/capabilities.md). If **any** capability's status is not `.granted`, the onboarding window opens and stays open until the user resolves it (or skips).

`OnboardingView` iterates the capability set and renders a row per capability. Each row shows:

- The capability's `displayName` ("Microphone", "Input Monitoring", "Accessibility").
- A one-line plain-English description of what it enables ("Detect the activation key", "Record audio for transcription", "Paste transcribed text at your cursor").
- Current status (`.granted` / `.denied` / `.unknown`).
- A `Grant` button that calls the capability's appropriate action:
  - **Microphone**: triggers the system prompt directly.
  - **Input Monitoring**: calls `openSystemSettings()` (creating the tap also triggers the prompt, but the explicit button is clearer).
  - **Accessibility**: calls `openSystemSettings()` with **explicit text instructions** rendered alongside: "Click +, navigate to /Applications/FreeFlow.app, and toggle it on. Then quit and relaunch Free Flow."

A `Refresh permission status` button calls `recheck()` on every capability without restarting the app.

A `Skip (I've already granted permissions)` button exists for unsigned dev builds where detection can be unreliable. **Why:** see [../architecture/permissions.md](../architecture/permissions.md). Skip bypasses the onboarding gate but does not silence individual capability checks — if a capability refuses an action at runtime, the failure still surfaces in the UI.

## Non-requirements (deliberately out of scope)

- Cloud transcription fallback.
- Multi-language UI (the dictation itself is multilingual via WhisperKit; the app UI is English-only).
- Mac App Store distribution.
- iOS / iPadOS support.
- Real-time streaming transcription (transcription happens after release, not during).

## Related

- [activation-key-and-mode.md](activation-key-and-mode.md) — the activation gesture in detail
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — the implementation of the cycle
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — how the menu bar renders state and errors (item 5)
- [../architecture/permissions.md](../architecture/permissions.md) — what each permission enables
