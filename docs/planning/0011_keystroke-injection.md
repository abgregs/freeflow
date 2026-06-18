# Planning: Keystroke Injection — Race-Free Text Insertion (roadmap 0011)

> **Status (2026-06-18): implemented; on-device validation rides the pre-v0.1.0 rc.**

Text insertion used the clipboard: snapshot the user's pasteboard → write the transcription → synthesize ⌘V → wait `clipboardRestoreDelay` → restore. The restore is timed against a paste we **cannot observe** — there is no OS signal for "the synthesized ⌘V was consumed," and a clipboard *read* doesn't bump `changeCount`. So on a slow target (e.g. the first dictation after launch while the model loads) the restore lands *before* the paste, and the user's **old clipboard** gets pasted instead of the transcription. The 250 ms delay only narrowed the window; it provably can't close it (the consume time is unbounded and unobservable).

## Fix: type the text, never touch the clipboard

Inject the transcription as **Unicode key events** via `CGEvent.keyboardSetUnicodeString`, routed through `AccessibilityCapability.postKeyEvent` (still the single `CGEvent.post` site). No clipboard write → no snapshot → no restore → **the race is gone by construction** (the app's "structurally impossible, not discipline" ethos). Bonuses:

- **No clipboard exposure at all.** Dictations never transit the system pasteboard, so 0006's "dictations transit the pasteboard" trade-off is *eliminated* and the 0007 transient/concealed markers become unnecessary — **0007 is superseded** and its marker code is removed.
- **Simpler.** `savePasteboard`/`restorePasteboard`/`writePasteboard`, the snapshot type, the restore-on-throw dance, and `clipboardRestoreDelay` all go away.

This does **not** violate "No AX-API path" ([free-flow-pipeline.md](../architecture/free-flow-pipeline.md)): that decision rejected AX *writes* (`AXUIElementSetAttributeValue`); this is input-event synthesis (`CGEvent`), the same family as the ⌘V it replaces.

## What's kept

- The **insertion guard** (`classifyFocusedTarget`, planning 0001) — still skip a clearly non-editable target.
- The **silent-no-op probe** in `postKeyEvent` — still confirms synthesized events land (runs on the first injected event).

## Race-free, not risk-free

Keystroke injection trades the clipboard race for a *different, smaller, testable* risk class:

- **Per-event length:** `keyboardSetUnicodeString` is unreliable past ~20 UTF-16 units in some apps → text is **chunked**, grapheme-safe (`Constants.keystrokeChunkUnits`).
- **Input-transforming apps:** auto-pairing of `(`/`{`/quotes and search-as-you-type fields can react per keystroke. Low risk for English prose; validate on-device.
- **Secure input fields:** synthesized keystrokes may be dropped when secure input is active. Unusual for dictation; accepted residual.
- **IME:** moot for V1 — `small.en` is English-only.

The down/up pairing, chunk size, and any inter-chunk gap are **on-device validation knobs**; the rc gates v0.1.0.

## Enables future streaming

Because insertion is now append-by-typing rather than one atomic paste, it's the right foundation for **append-only streaming dictation** (commit stable-prefix words as they finalize during recording). Streaming itself is a larger, separate effort (incremental transcription + a stabilization layer + a session-cycle change); 0011 just stops foreclosing it — clipboard-paste did.

## Acceptance criteria

1. Dictation inserts correctly across native AppKit, a browser, an Electron app, and a terminal — verified on the pre-v0.1.0 rc.
2. The clipboard is never read or written (verifiable: no pasteboard APIs remain in `TextInsertionManager`).
3. The insertion guard and the silent-no-op probe still function.

## Related

- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — the insertion step and the "No AX-API path" decision
- [0007_transient-pasteboard-markers.md](0007_transient-pasteboard-markers.md) — superseded by this
- [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md) — the pasteboard-transit trade-off this eliminates
- [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md) — the insertion guard, retained
