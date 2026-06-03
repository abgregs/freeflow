# ADR 0001: Defer protocol seams for cycle collaborators

**Status:** Accepted — 2026-06-03

## Context

`RiverSession` takes concrete `HotkeyManager`, `AudioCaptureManager`, `TranscriptionService`, and `TextInsertionManager`. Their real implementations call OS or network APIs — `CGEvent.tapCreate`, `AVAudioEngine.start`, WhisperKit model load + transcribe, `CGEvent.post`.

The test runner can't satisfy several of these in CI (no Input Monitoring grant; sometimes a Microphone grant; no Accessibility grant; no network for model download). The pattern landed in M4–M5 to keep tests hermetic is per-class **`skip*ForTesting`** flags plus `publishForTest` seams for synthetic event injection:

- `InputMonitoringCapability` gets it free (`CGEvent.tapCreate` returns nil without IM grant).
- `MicrophoneCapability.skipEngineForTesting` (M5).
- M6's `TranscriptionService` would carry the same shape.

The architecturally clean alternative is to extract protocols (`Transcriber`, `AudioCapture`, `HotkeyInput`, eventually a `TextInsertion` interface) and have `RiverSession` depend on existentials, with `Fake*` conformers in tests.

## Decision

Defer the protocol extraction. Keep concrete cycle collaborators + `skip*ForTesting` flags + `publishForTest` seams as the testability pattern for now.

## Rationale

- **Scale.** One dictation cycle, one real implementation per role. Three protocols + three fakes is meaningful surface area for code that currently has exactly one user of each interface.
- **The seam is named, just not promoted.** Each `skip*ForTesting` flag lives on the concrete type with a `// internal for testability` comment explaining *why* the OS call won't fail naturally in tests. The seam is visible — it just doesn't have a protocol declaration.
- **Tests are fast and deterministic.** ~0.7 s for the full suite as of M5; no protocol indirection on the hot path.
- **The cycle is still gaining capability.** M6/M7 will sharpen what the manager interfaces need to do. Locking them as protocols now would freeze them before the requirements are stable.
- **Premature `Manager` protocols are a known dead end** in this app's lineage — the predecessor had several "*Protocol" facades that existed only for tests and slowly accreted production-only methods, defeating their purpose.

## Consequences

- Cycle tests exercise **failure paths** cleanly via skip flags (e.g., M6's `transcribe` throws `.modelNotLoaded` when `loadModel` was never called). Tests verify "the cycle handles the failure and returns to `.idle`."
- Cycle tests **cannot** inject a fake "successful transcription with text `'hello'`" without standing up a real WhisperKit. Success-path validation for the user-visible loop is **manual on-device** until that gap matters.
- Every new cycle collaborator that touches an OS/network API will need to carry the same skip-flag pattern. This is a tax, but a small one (~3 lines per type).

## Revisit if

- **A second adapter becomes desired.** Examples: MLX-Whisper or Whisper.cpp as an alternative transcription backend (would compete for the "fast + accurate" goal); a cloud STT fallback; an alternative audio source (system audio capture for meetings).
- **Skip flags spread to a fifth+ module.** At that point the per-class pattern is more weight than three protocols + fakes.
- **Cycle tests start needing to inject success-path scenarios** (e.g., to verify that `M7` correctly hands transcribed text `'X'` to `TextInsertionManager` without going through WhisperKit). Today that's covered by manual on-device verification; if it becomes a fast-feedback need, the protocol seams pay for themselves.
- **The fakes-required-for-testability list grows organically** to cover more than the one OS/network call each — e.g., if a manager gains complex internal logic that's worth testing through a fake of a different manager, the protocol approach gets cleaner-per-line.

## Related

- [../conventions/tests.md](../conventions/tests.md) — the access-seams list documents every `skip*ForTesting` and `publishForTest` seam currently in play.
- [../conventions/swift-style.md](../conventions/swift-style.md) — the `Manager` suffix convention for state-owning cycle collaborators.
