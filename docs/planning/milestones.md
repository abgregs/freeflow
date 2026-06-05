# Planning: Milestones

Ordered. Each milestone is a state the project can pause at without being broken. Milestones are *outcomes*, not task lists — the agent decomposes each into tasks via `/brief`.

The first three milestones (M1–M3) establish the architectural skeleton — bundle pipeline, capability layer, dictation session — before any feature code is written. M4–M9 fill the session interior. M10–M11 cover distribution.

## M1: Walking skeleton

A signed, installable menu bar app that does nothing useful. Proves the build, sign, and install pipeline before any feature code is written. Also establishes the architectural skeleton: empty `Capability` protocol declarations, an empty `SettingsStore`, a stub `FreeFlowSession` that does nothing. See [walking-skeleton.md](walking-skeleton.md) for the detailed acceptance criteria.

## M2: Capability layer + onboarding

The three [`Capability`](../architecture/capabilities.md) implementations exist, each with a real `recheck()` that returns `.granted` / `.denied` / `.unknown` honestly. `OnboardingView` iterates the capability set and opens on launch whenever any status is not `.granted`. Per-capability `Grant` buttons work — Microphone auto-prompts, Input Monitoring and Accessibility deep-link to System Settings with explicit instructions. `Refresh permission status` calls `recheck()` on every capability. `Skip` button works for dev builds.

Exit criteria: a user installing from a `.dmg` and following onboarding can grant all three permissions and reach the menu bar with the icon visible. The "lying permission check" and "onboarding only on hard failure" anti-patterns are structurally impossible at this point.

## M3: FreeFlowSession skeleton

[`FreeFlowSession`](../architecture/free-flow-session.md) exists with the public interface (`start()` / `stop()` / `state` publisher). It owns the `FreeFlowState` machine, holds references to (empty stub) managers, and subscribes to [`SettingsStore`](../architecture/settings-store.md) publishers — even though the store has no keys yet beyond placeholders. `AppDelegate` shrinks to construct-and-start.

Exit criteria: launching the app yields a menu bar with state visible via `FreeFlowSession.state.idle`. No actual dictation happens; the wiring is the test surface. A unit test drives `session.start()` and asserts the initial state.

## M4: Hotkey detection (Hold mode)

`InputMonitoringCapability` owns the real `CGEventTap` on `com.freeflow.eventtap`. `HotkeyManager` consumes its event stream and fires semantic `onActivate` / `onDeactivate` callbacks. Default activation key Right Option (keycode 61 — universal on every Mac keyboard including MacBook and the compact Magic Keyboard); Hold mode only. `FreeFlowSession` transitions to `.recording` / `.idle` in response.

Exit criteria: holding Right Control transitions the session to `.recording`; releasing transitions back to `.idle`. Tested with synthetic events fed into `InputMonitoringCapability`'s internal helpers. Tap self-heals on `.tapDisabledByTimeout`.

## M5: Audio capture

`MicrophoneCapability` owns audio-engine start/stop. `AudioCaptureManager` records hardware-format audio while held; converts to 16 kHz mono Float32 on stop. Handles the engine-warmup race (wait for first buffer before teardown). `FreeFlowSession` calls into the manager during `.recording`.

Exit criteria: pressing the key, speaking, releasing produces a non-empty audio sample array of expected length. Short taps (< 200 ms) produce real audio, not silently dropped.

## M6: Transcription

WhisperKit integrated. Default model loads on launch (on its own schedule, not blocking the session). `TranscriptionService.transcribe` returns text or a typed error. Custom dictionary integration with the special-token filter in place. `FreeFlowSession` calls into the service during `.processing`.

Exit criteria: a 3+ second utterance returns a non-empty transcription that's a reasonable approximation of what was said.

## M7: Text insertion

`AccessibilityCapability.postKeyEvent(...)` is the only path that calls `CGEvent.post`. `TextInsertionManager` saves the pasteboard, writes the transcription, calls into the capability, restores after 250 ms. Capability includes the silent-no-op detector. Error strings log `privacy: .public` but path-redacted via `LogRedaction`; user content is protected by omission (see [ADR 0002](../decisions/0002-log-redaction-over-debug-flag.md)).

Exit criteria: end-to-end test in Notes: hold key, speak, release, transcribed text appears at cursor. Clipboard restored afterward. Original clipboard contents preserved. If the capability is missing or misconfigured, the cycle aborts with a visible error and onboarding opens.

## M8: SettingsStore + Settings UI

[`SettingsStore`](../architecture/settings-store.md) exists with typed per-key publishers. `Settings` namespace declares all keys with defaults. `SettingsView` with Activation section (key + mode pickers, warnings), Custom Dictionary section, model picker, launch-at-login, pause-media toggle. All SwiftUI bindings use `@AppStorage(Settings.x.name)`. `FreeFlowSession` subscribes to the activation publishers and applies live (or defers during a cycle).

Exit criteria: every documented setting changes the app's behavior without restart. Changing the activation key during an active recording does not drop the recording. The `pendingReconfiguration` deferral is verifiable via a unit test on `FreeFlowSession`.

## M9: Tap modes (Single Tap, Double Tap)

`TapStateMachine` with explicit `State` enum. Wired into `HotkeyManager` so non-Hold modes route through it. Live-apply when mode changes via Settings flows through the same `FreeFlowSession` subscription as M8.

Exit criteria: tests for state machine cover single-tap, double-tap within window, double-tap outside window, boundary, and stop-via-single-tap. End-to-end: all three modes work in Notes.

## Focused-element paste guard

Before posting the synthesized ⌘V, verify the system-wide focused element is a text-bearing AX role; skip the paste and signal "no text field focused" otherwise. A **read-only** AX role check — not the AX write path rejected in [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md). Catches the "dictate into a non-editable target" case (e.g. a selected DOM node in browser dev tools) that today fires a stray paste indistinguishable from success. Sequenced after the Menu-bar visual-state milestone, whose session-level error surface it reuses. Detail: [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md).

Exit criteria: non-editable focus produces no paste, a visible signal, and an untouched clipboard; editable focus pastes as today; an ambiguous AX role fails open. Role classification is unit-tested off a role table.

## M10: Local-install distribution

Makefile target that does `swift build -c release`, assembles the bundle (`Info.plist` + entitlements), installs to `/Applications`, and signs with the local "Free Flow Dev" identity. README documents the one-time keychain certificate setup. Bundle assembly is verified with `codesign -dv` before install completes.

Exit criteria: `make install` produces a working `/Applications/FreeFlow.app` that survives across rebuilds without re-granting permissions. The bundle-misidentification failure mode is detected by `AccessibilityCapability` at runtime if it ever occurs.

## M11: Public release pipeline

GitHub Action: on tag, build with Developer ID signing, notarize via `notarytool`, staple, package as `.dmg`, attach to release. Homebrew cask in a separate `homebrew-freeflow` tap repo pointing at the release artifact.

Exit criteria: `git tag v0.1.0 && git push origin v0.1.0` results in a downloadable signed/notarized `.dmg` on the GitHub release page within 10 minutes.

## Beyond

Tracked as open items in [_index.md](_index.md). Examples: slider for `doubleTapWindowMs`, Fn-key warning, mid-cycle settings change visual feedback.
