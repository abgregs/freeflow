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

1. **[`InputMonitoringCapability`](capabilities.md)** owns the `CGEventTap` on `.flagsChanged`. It exposes raw flag-change events as a typed stream. **`HotkeyManager`** consumes that stream, interprets it against the configured `ActivationKey` and `ActivationMode`, and fires semantic `onActivate` / `onDeactivate` callbacks (Hold mode: key-down; tap modes: complete tap or confirmed double-tap).
2. **`FreeFlowSession.handleActivate`** transitions state to `.recording` and asks `AudioCaptureManager` to start.
3. **`AudioCaptureManager`** (using [`MicrophoneCapability`](capabilities.md)) taps the input node in **hardware format** (whatever the device gives us — typically 44.1 / 48 kHz) and accumulates copies of `AVAudioPCMBuffer`. **Why hardware format and not 16 kHz at capture time:** doing sample-rate conversion inside the tap callback risks losing audio if the converter stalls. Convert at stop time instead.
4. On **`onDeactivate`**, `FreeFlowSession` asks `AudioCaptureManager.stopRecording()`. The manager waits briefly for the first buffer if none arrived yet (see "Engine warmup" below), then concatenates buffers and converts to 16 kHz mono Float32 via `AVAudioConverter`.
5. **`TranscriptionService.transcribe(audioSamples:)`** runs WhisperKit with `DecodingOptions.promptTokens` seeded from the custom dictionary. **Custom-dictionary tokenization rule:** filter out tokens >= `tokenizer.specialTokens.specialTokenBegin`. **Why:** special tokens injected into `promptTokens` corrupt decoding silently.
6. **`TextInsertionManager.insertText(_:)`** saves the full pasteboard, writes the transcription, asks [`AccessibilityCapability.postKeyEvent(...)`](capabilities.md) to synthesize ⌘V, and restores the original pasteboard after `Constants.clipboardRestoreDelay` (default 250 ms). The capability is responsible for the actual `CGEvent.post` call and for refusing if its status isn't `.granted`.
7. `FreeFlowSession` sets state back to `.idle`. If a configuration change arrived during the cycle (see [free-flow-session.md](free-flow-session.md) on deferred reconfiguration), it is applied here.

## Engine warmup

`AVAudioEngine.start()` returns synchronously, but the input-tap callback only fires once the engine has produced its first buffer (~60–100 ms warmup). A short tap that ends inside that window would otherwise drop the entire utterance.

`AudioCaptureManager.stopRecording()` therefore waits up to **300 ms** for at least one buffer to arrive before tearing down. Normal-length presses are unaffected — the wait loop exits immediately when buffers already exist.

## No AX-API path

Text insertion is always clipboard + synthesized ⌘V through `AccessibilityCapability`. There is no Accessibility-API write path. **Why:** AX writes require per-app focus targeting that is brittle across browsers, Electron apps, and terminal emulators. Clipboard + ⌘V is uniformly supported wherever ⌘V works.

The cost is that the user's clipboard is briefly replaced. We mitigate by saving and restoring all items and types, with a 250 ms gap to let the paste land.

## Capability failures are typed errors

If `AccessibilityCapability.postKeyEvent` throws (status not `.granted`, or the silent-no-op detector fires), `TextInsertionManager` propagates the error to `FreeFlowSession`. The session logs at `.error`, updates `appState.errorMessage`, and returns to `.idle`. The user sees the error reflected in the UI; nothing fails silently.

Audio capture follows the same pattern via `AudioCaptureError` (`.noAudioCaptured` when no buffer arrives in the 300 ms engine-warmup window; `.conversionFailed` when `AVAudioConverter` errors). `FreeFlowSession.handleDeactivate` catches both, logs at `.error`, and still returns to `.idle` — getting stuck in `.processing` would freeze the cycle. Note: `MicrophoneCapability.startEngine` itself does **not** throw (a failure to start logs a warning; the capability's `status` is the surface that signals "engine won't work" upstream to onboarding). The fail-loud surface is `stopRecording`, which is where "did we actually capture audio" becomes knowable.

## Related

- [free-flow-session.md](free-flow-session.md) — the module that owns the orchestration and state machine
- [capabilities.md](capabilities.md) — the per-permission modules each step depends on
- [threading-invariant.md](threading-invariant.md) — why the event tap thread matters
- [permissions.md](permissions.md) — user-facing description of what each capability enables
- [../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md) — Hold vs. Single Tap vs. Double Tap semantics
