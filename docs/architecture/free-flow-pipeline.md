# Architecture: Free Flow Pipeline

One full cycle from keypress to pasted text. `FreeFlowState` is the lock; [`FreeFlowSession`](free-flow-session.md) is the only writer.

## States

```
.idle ──key down──> .recording ──key up──> .processing ──transcribe done──> .idle
```

- **.idle** — accepting new activations.
- **.recording** — mic is capturing into `AVAudioPCMBuffer`s; new activations are ignored.
- **.processing** — engine torn down, WhisperKit running, paste pending; new activations are ignored.

Re-entrancy is safe: every transition is guarded by `guard state == expected` before mutating. Stale callbacks log and return.

## Steps

1. **[`InputMonitoringCapability`](capabilities.md)** owns the `CGEventTap` on `.flagsChanged`. It exposes raw flag-change events as a typed stream. **`HotkeyManager`** consumes that stream, interprets it against the configured `ActivationKey` and `ActivationMode`, and fires semantic `onActivate` / `onDeactivate` callbacks. Hold mode is interpreted inline (key-down activates, key-up deactivates); the tap modes route each completed tap through **`TapStateMachine`** (a single completed tap, or a confirmed double-tap within ~400 ms).
2. **`FreeFlowSession.handleActivate`** transitions state to `.recording` and asks `AudioCaptureManager` to start.
3. **`AudioCaptureManager`** (using [`MicrophoneCapability`](capabilities.md)) taps the input node in **hardware format** (whatever the device gives us — typically 44.1 / 48 kHz) and accumulates copies of `AVAudioPCMBuffer`. **Why hardware format and not 16 kHz at capture time:** doing sample-rate conversion inside the tap callback risks losing audio if the converter stalls. Convert at stop time instead.
4. On **`onDeactivate`**, `FreeFlowSession` asks `AudioCaptureManager.stopRecording()`. The manager waits briefly for the first buffer if none arrived yet (see "Engine warmup" below), then concatenates buffers and converts to 16 kHz mono Float32 via `AVAudioConverter`.
5. **`TranscriptionService.transcribe(audioSamples:)`** runs WhisperKit with `DecodingOptions.promptTokens` seeded from the custom dictionary. **Custom-dictionary tokenization rule:** filter out tokens >= `tokenizer.specialTokens.specialTokenBegin`. **Why:** special tokens injected into `promptTokens` corrupt decoding silently.
6. **`TextInsertionManager.insertText(_:)`** first runs the **paste guard**: a read-only focused-element role check via `AccessibilityCapability.classifyFocusedTarget()`. A clearly non-editable target (a focused button, a dev-tools DOM selection) skips the paste with `TextInsertionError.noEditableTarget` — clipboard untouched, "No text field focused" surfaced via the `errors` publisher; an undeterminable role fails open. Otherwise it saves the full pasteboard, writes the transcription, asks [`AccessibilityCapability.postKeyEvent(...)`](capabilities.md) to synthesize ⌘V, and restores the original pasteboard after `Constants.clipboardRestoreDelay` (default 250 ms). The capability is responsible for the actual `CGEvent.post` call and for refusing if its status isn't `.granted`.
7. `FreeFlowSession` sets state back to `.idle`. If a configuration change arrived during the cycle (see [free-flow-session.md](free-flow-session.md) on deferred reconfiguration), it is applied here.

## Engine warmup

`AVAudioEngine.start()` returns synchronously, but the input-tap callback only fires once the engine has produced its first buffer (~60–100 ms warmup). A short tap that ends inside that window would otherwise drop the entire utterance.

`AudioCaptureManager.stopRecording()` therefore waits up to **300 ms** for at least one buffer to arrive before tearing down. Normal-length presses are unaffected — the wait loop exits immediately when buffers already exist.

## No AX-API path

Text insertion is always clipboard + synthesized ⌘V through `AccessibilityCapability`. There is no Accessibility-API write path. **Why:** AX writes require per-app focus targeting that is brittle across browsers, Electron apps, and terminal emulators. Clipboard + ⌘V is uniformly supported wherever ⌘V works.

The cost is that the user's clipboard is briefly replaced. We mitigate by saving and restoring all items and types, with a 250 ms gap to let the paste land.

**One read-only exception — the paste guard** ([planning 0001](../planning/0001_focused-element-paste-guard.md)): before attempting the paste, `TextInsertionManager` asks `AccessibilityCapability.classifyFocusedTarget()` to read the system-wide focused element's AX role (`AXUIElementCreateSystemWide` → `kAXFocusedUIElementAttribute` → role/subrole) and skips the ⌘V when the role is clearly non-editable, throwing `TextInsertionError.noEditableTarget` before the pasteboard is touched. An undeterminable role **fails open** — the paste is attempted exactly as before. This refines rather than reverses the decision above: what was rejected is AX *writes* as the insertion mechanism; the guard is a role *read* that only gates whether the clipboard + ⌘V path runs, and the read happens in `AccessibilityCapability` so AX calls keep a single owner.

## Capability failures are typed errors

If `AccessibilityCapability.postKeyEvent` throws (status not `.granted`, or the silent-no-op detector fires), `TextInsertionManager` restores the original pasteboard immediately, rethrows, and `FreeFlowSession.handleDeactivate` catches the error, logs at `.error` (path-redacted per [ADR 0002](../decisions/0002-log-redaction-over-debug-flag.md)), and returns to `.idle`. There are now **two** user-visible surfaces:

- **Permission-misconfigured path** — structural. The silent-no-op detector calls `update(.denied)` on the capability, which `OnboardingCoordinator` observes as a `.granted → !.granted` transition and re-presents onboarding with permission-specific copy.
- **Transient cycle failures** (a momentary `cghidEventTap` refusal, a transcription or capture error) — the session emits a typed `FreeFlowError` on its `errors` publisher. [`AppState`](app-state-and-menu-bar.md) bridges that to the menu bar, which shows a warning glyph over the idle icon plus the (path-redacted) message. The emission never blocks the return to `.idle`.

This is the surface the menu-bar visual-state milestone landed (it brought the renderer and the `errors` publisher together, as planned). It is **not** a substitute for the permission path above — a genuinely denied capability still routes through onboarding, not a transient toast.

Audio capture follows the same pattern via `AudioCaptureError` (`.noAudioCaptured` when no buffer arrives in the 300 ms engine-warmup window; `.conversionFailed` when `AVAudioConverter` errors). `FreeFlowSession.handleDeactivate` catches both, logs at `.error`, and still returns to `.idle` — getting stuck in `.processing` would freeze the cycle. Note: `MicrophoneCapability.startEngine` itself does **not** throw (a failure to start logs a warning; the capability's `status` is the surface that signals "engine won't work" upstream to onboarding). The fail-loud surface is `stopRecording`, which is where "did we actually capture audio" becomes knowable.

## Related

- [free-flow-session.md](free-flow-session.md) — the module that owns the orchestration and state machine
- [app-state-and-menu-bar.md](app-state-and-menu-bar.md) — how `FreeFlowError` and `state` reach the menu bar via the `AppState` bridge
- [capabilities.md](capabilities.md) — the per-permission modules each step depends on
- [threading-invariant.md](threading-invariant.md) — why the event tap thread matters
- [permissions.md](permissions.md) — user-facing description of what each capability enables
- [../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md) — Hold vs. Single Tap vs. Double Tap semantics
