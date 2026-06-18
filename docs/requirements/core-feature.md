# Requirement: Core Feature

## User story

> As a Mac user, I press (or tap) a configurable modifier key, speak, release (or tap again), and my words appear as text wherever my cursor is focused — without my voice or text leaving my device.

## Acceptance criteria

1. **Activation works.** The configured activation key triggers recording per the selected mode (see [activation-key-and-mode.md](activation-key-and-mode.md)).
2. **Recording captures real audio.** Pressing the key (Hold mode) or completing a tap (tap modes) produces a non-empty audio buffer for any utterance ≥ ~100 ms. Recording of length 0 must not silently succeed; either capture or fail loudly.
3. **Transcription happens locally.** WhisperKit runs on-device. No network call for the transcription itself.
4. **Text appears at the cursor.** The transcription is typed in as synthesized Unicode keystrokes into whatever text field currently has focus — **the clipboard is never touched** (no copy/paste, nothing to restore). When the focused element is clearly non-editable (a focused button, a selected list row or DOM node), insertion is skipped and the menu bar shows "No text field focused"; an ambiguous target proceeds (fail-open). See the insertion guard and "No AX-API path" in [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md).
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

A `Skip (I've already granted permissions)` button exists in local/self-signed dev builds, where detection can be unreliable — it is **compiled out of notarized release builds** via the `FREEFLOW_RELEASE` flag (see [../planning/0005_release-pipeline-security.md](../planning/0005_release-pipeline-security.md)), because a notarized app has reliable detection and a Skip would only let a user bypass a still-required permission. **Why it exists at all:** see [../architecture/permissions.md](../architecture/permissions.md). Skip bypasses the onboarding gate but does not silence individual capability checks — if a capability refuses an action at runtime, the failure still surfaces in the UI.

## Non-requirements (deliberately out of scope)

- Cloud transcription fallback.
- Non-English dictation. The default model is Whisper's English-only `small.en` variant, so dictation only supports English for now; that may change later (the planned model picker is the natural seam for offering multilingual variants). **Why:** at the model sizes Free Flow targets, the `.en` variants transcribe English measurably better than the same-size multilingual model and can't misdetect the spoken language.
- Multi-language UI (the app UI is English-only).
- Mac App Store distribution.
- iOS / iPadOS support.
- Real-time streaming transcription (transcription happens after release, not during).

## Related

- [activation-key-and-mode.md](activation-key-and-mode.md) — the activation gesture in detail
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — the implementation of the cycle
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — how the menu bar renders state and errors (item 5)
- [../architecture/permissions.md](../architecture/permissions.md) — what each permission enables
