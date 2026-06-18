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
- `audio` — `MicrophoneCapability` engine start/stop + input format; `AudioCaptureManager` capture lifecycle, sample count, and conversion failures
- `transcribe` — `TranscriptionService`: WhisperKit model-load lifecycle (start / loaded / failed), transcribe start (sample count), end (transcribed char count). **Never** log the transcribed text itself — that's user content (anti-pattern #4)
- `insert` — `TextInsertionManager` keystroke injection (typing the transcription at the cursor)

Pick the category that matches where the code lives. Adding new categories is fine; reusing categories across files is fine when they share a concern.

## Levels

- `.info` — normal lifecycle and state transitions. The bread and butter of the log.
- `.warning` — recoverable but unexpected (e.g., "tap was disabled by system, re-enabling").
- `.error` — something failed. Always include the failure reason.
- `.debug` — verbose internal detail; off by default in user-visible filtering.
- `.fault` — programmer error / invariant violation.

## Privacy: omission for content, redaction for paths

`os.Logger` redacts dynamic **string** interpolations as `<private>` by default and shows scalars (counts, lengths, state names) in the clear. Two rules build on that, and the privacy boundary is held *without* a verbose/debug build mode (see [ADR 0002](../decisions/0002-log-redaction-over-debug-flag.md) for why the old `DICTATION_VERBOSE_LOGS` flag was dropped).

### 1. User content is never logged — at any privacy level

Transcribed text and custom dictionary terms are kept *out of the format string entirely*. Log a `.count` or length, never the value. This is structural: there is no `privacy:` annotation to get wrong because the content is never interpolated.

```swift
logger.info("Transcribed \(text.count, privacy: .public) chars")   // length OK
// logger.info("Transcription: '\(text)'")                          // NEVER
```

### 2. Error strings are public, but path-redacted

The failure *reason* is the most valuable line in a bug report, so error strings are logged `privacy: .public` to stay visible in the field. But an opaque third-party/OS `error.localizedDescription` can embed a filesystem path like `/Users/<name>/...` that carries the macOS account name. Pass every logged error string through `LogRedaction.redactUserPaths(_:)`, which strips it deterministically:

```swift
logger.error("WhisperKit load failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
```

`redactUserPaths` is idempotent and a no-op on app-authored error strings, so it's applied uniformly at *every* error-string log site — no per-site judgment about whether a value is "opaque enough." App-authored error descriptions (e.g. `AudioCaptureError`) carry no PII, but they pass through the same call so the rule stays mechanical.

### Non-sensitive scalars are public directly

Sample counts, character counts, state names, keycodes — logged `privacy: .public` with no wrapper. They're the bread-and-butter diagnostic signal and contain no PII.

```swift
logger.info("State -> processing")                                 // state name, public
logger.info("Captured \(samples.count, privacy: .public) samples") // count, public
```

## Related

- [../architecture/permissions.md](../architecture/permissions.md) — diagnosing permission failures depends on seeing real error messages
- [anti-patterns.md](anti-patterns.md) — item #4: logging user content / trusting an opaque error string
- [../decisions/0002-log-redaction-over-debug-flag.md](../decisions/0002-log-redaction-over-debug-flag.md) — why path-redaction at the source replaced the verbose-build flag
