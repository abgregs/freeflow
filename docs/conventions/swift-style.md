# Conventions: Swift Style

## Naming

- **Types**: `UpperCamelCase`. The cycle's state-owning collaborators under `Managers/` use the `Manager` suffix uniformly — `HotkeyManager`, `AudioCaptureManager`, `TextInsertionManager`, and `TranscriptionManager` (renaming `TranscriptionService` is tracked in [../planning/_index.md](../planning/_index.md)). Pure value types and stateless helpers use behavioral names without a suffix (e.g., `TapEvent`, `OnboardingGate`, `SystemSettingsPane`). **Why:** consistency across the `Managers/` folder beats per-name micro-optimization; the suffix signals "owns significant state and an OS/network surface" at a glance.
- **Identifiers**: descriptive — no single-letter locals outside trivial closures, no abbreviations except universally understood ones (`url`, `id`, `db`).
- **Booleans**: positive phrasing, predicate form. `isRecording`, `hasPendingRestart`, never `recordingFlag` or `notIdle`.
- **Enums for state**: prefer explicit case names over booleans. `enum State { case idle, recording, processing }` not three `Bool`s.

## Access control

- **Default to `internal`.** Don't write `public` unless the type is part of a deliberate public API.
- **`private` only when you're sure the rest of the module shouldn't see it.** Over-eager `private` blocks tests. See [tests.md](tests.md).
- **Test seams stay `internal`.** A symbol exposed at `internal` specifically for tests is documented inline with `// internal for testability`. Do not promote it to `public`.

## File layout

- One primary type per file. File name matches the type: `HotkeyManager.swift` defines `HotkeyManager`.
- Folders mirror responsibility: `App/`, `Managers/`, `Models/`, `Services/`, `Views/`, `Utilities/`, `Resources/`.
- Small helpers can live in the same file as the type they support.

## When to extract a type

- Extract when a chunk of logic is independently testable. Example: `TapStateMachine` is its own type because it can be unit-tested with synthetic events; if it lived inside `HotkeyManager`, it would require a real `CGEventTap`.
- Don't extract a type just to have a smaller file. Length is a code smell to investigate, not a problem to solve by moving code.
- **Why:** premature abstraction is the most common over-engineering trap. The audit pattern is: "if I deleted this type, would anything else break?" If only the surrounding type uses it and no test does, it shouldn't be a separate type.

## Comments

- Default to none. Identifiers should speak for themselves.
- Add a comment only when the **why** is non-obvious — a hidden constraint, a workaround for a specific OS bug, a subtle invariant. **Why:** comments rot; code doesn't. A misleading comment is worse than no comment.
- Avoid multi-paragraph docstrings. One line, max.
- Never document **what** the code does. Document **why** it does it that way.

## Error handling

- Throw at boundaries (file I/O, network, system APIs); use typed errors where reasonable (`enum AudioCaptureError: LocalizedError`).
- Catch only where you can do something useful. Don't wrap an error in another error just to add a stack frame.
- Never silently swallow an error. If the right behavior is "log and continue," log at `.error` and continue explicitly.

## Concurrency

- `@MainActor` on anything that mutates UI state or `AppState`.
- Tap callbacks from background threads always hop back to `@MainActor` via `Task { @MainActor in ... }` before touching shared state.
- Do not use `DispatchQueue.main.sync` inside event-tap callbacks. See [../architecture/threading-invariant.md](../architecture/threading-invariant.md).

## Related

- [tests.md](tests.md) — access-control implications for testability
- [anti-patterns.md](anti-patterns.md) — what not to do
