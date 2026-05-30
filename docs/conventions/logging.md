# Conventions: Logging

`os.Logger` everywhere. No `print`. Categories per subsystem.

## Subsystem and categories

```swift
private let logger = Logger(subsystem: "com.freeflow.app", category: "app")
```

Categories in use:

- `app` — `AppDelegate` lifecycle, `FreeFlowSession` state transitions
- `permissions` — `Capability` status checks and the onboarding grant flow
- `hotkey` — `HotkeyManager` events, restart, tap status
- `audio` — `AudioCaptureManager` start/stop, format
- `transcribe` — `TranscriptionService` model load, transcription start/end
- `insert` — `TextInsertionManager` clipboard write/verify/restore

Pick the category that matches where the code lives. Adding new categories is fine; reusing categories across files is fine when they share a concern.

## Levels

- `.info` — normal lifecycle and state transitions. The bread and butter of the log.
- `.warning` — recoverable but unexpected (e.g., "tap was disabled by system, re-enabling").
- `.error` — something failed. Always include the failure reason.
- `.debug` — verbose internal detail; off by default in user-visible filtering.
- `.fault` — programmer error / invariant violation.

## Privacy redaction — the explicit opt-in

By default, **all interpolated values are redacted as `<private>` in `os_log` output unless explicitly marked `public`.** This is correct for production: it protects user content (transcribed text, dictionary terms, etc.) from leaking into logs that the user might share for debugging.

But during development, redaction makes log-based diagnosis painful. **A core failure mode of debugging this app is "I can't see the error message because it's redacted."**

### The pattern

Two rules:

1. **User content stays private.** Transcribed text, custom dictionary terms, clipboard contents — these never go to logs as `privacy: .public`. Period.
2. **Diagnostic context (error messages, counts, lengths, state names) is selectively public, gated on a build flag.**

The build flag is `--debug true` passed to the build script. When set, the build does two things:

- Sets a compile-time flag `DICTATION_VERBOSE_LOGS` that the source code can `#if`-guard around `privacy: .public` annotations on selected logging calls (errors, sizes, state transitions).
- **Prints a warning before the build runs:**

  ```
  ⚠️  --debug true: building with verbose logs.
      Error messages and diagnostic counts will be visible in os_log output
      (not redacted as <private>). User content like transcribed text remains private.
      Do NOT use this build for distribution.
  ```

The user must read this warning before the build proceeds. **Why:** an explicit, one-line opt-in stops anyone from accidentally shipping a binary with verbose logging enabled. The warning is a confirmation that the developer knows what mode they're building in.

### Examples

```swift
// Always-public: state machinery, non-sensitive counts.
logger.info("State -> processing")
logger.info("Audio captured: \(sampleCount) samples")

// Conditionally public: error strings (we want these visible for debugging
// but they could occasionally include paths or other contextual info).
#if DICTATION_VERBOSE_LOGS
logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
#else
logger.error("Transcription failed: \(error.localizedDescription)")
#endif

// Never public: actual user content.
logger.info("Transcription succeeded, length=\(text.count)")  // length OK
// logger.info("Transcription: '\(text)'")                    // text NOT OK
```

## Related

- [../architecture/permissions.md](../architecture/permissions.md) — diagnosing permission failures depends on seeing real error messages
- [anti-patterns.md](anti-patterns.md) — the "always-public logging" anti-pattern
