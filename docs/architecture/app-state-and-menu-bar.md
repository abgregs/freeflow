# Architecture: AppState and the menu bar

How the UI observes the dictation cycle without the cycle knowing the UI exists.

[`FreeFlowSession`](free-flow-session.md) is deliberately UI-agnostic — it imports no SwiftUI and exposes Combine publishers (`state`, `errors`). `AppState` is the thin bridge that turns those publishers into something SwiftUI can observe; the menu bar reads `AppState`. **Why:** the session stays a pure cycle owner and the test surface, while the UI stays a pure function of observed state. Neither reaches into the other.

## AppState — the Combine → `@Observable` bridge

`AppState` is `@MainActor @Observable` and holds exactly what the UI renders:

```swift
@MainActor @Observable
final class AppState {
    private(set) var state: FreeFlowState = .idle
    private(set) var errorMessage: String?
    func bind(to session: FreeFlowSession)   // sinks session.state + session.errors
}
```

`AppDelegate` constructs one `AppState`, calls `bind(to: session)` once at launch, and hands it to the `MenuBarExtra`. The `cancellables` set is `@ObservationIgnored` so subscription bookkeeping doesn't trip observation.

Two rules live in the update entry points (both `internal` for testability — see [../conventions/tests.md](../conventions/tests.md)):

- **`apply(_ state:)`** — a fresh `.recording` clears `errorMessage`, so the menu never shows last cycle's failure over a new attempt.
- **`apply(_ error:)`** — the **single choke point** where a `FreeFlowError` becomes display text. It runs `LogRedaction.redactUserPaths(_:)` exactly once here, so a `/Users/<name>` path in a framework error can't ride onto the menu (and into a screenshot). This is the UI half of [ADR 0002](../decisions/0002-log-redaction-over-debug-flag.md); the log half redacts at the log sites.

## FreeFlowError — the cycle-failure surface

`FreeFlowSession` exposes `var errors: AnyPublisher<FreeFlowError, Never>`. `FreeFlowError` has one case per cycle stage (`.audioCapture` / `.transcription` / `.textInsertion`, each wrapping the underlying error). `handleDeactivate` emits the matching case from each stage's `catch` **without disturbing the return to `.idle`** — the error is a side signal, not a control-flow change (the cycle still always lands back at `.idle`; see [free-flow-pipeline.md](free-flow-pipeline.md)).

## MenuBarPresentation — pure state → visuals

The icon/label contract is a pure function, extracted from the view so it's unit-tested without standing up SwiftUI:

```swift
enum MenuBarPresentation {
    struct Visual: Equatable { let systemImage: String; let statusLabel: String }
    static func visual(state: FreeFlowState, hasError: Bool) -> Visual
}
```

Mapping (per [../requirements/core-feature.md](../requirements/core-feature.md) item 5):

| State | Icon | Label |
|---|---|---|
| `.idle` | `mic` | Ready |
| `.recording` | `mic.fill` | Recording... |
| `.processing` | `ellipsis` | Processing... |

A pending error overrides **only the `.idle` icon** with `exclamationmark.triangle`; an active state's icon always wins (errors surface at end-of-cycle, so a live `.recording`/`.processing` glyph is never masked by a stale error). The label always reflects the raw state.

`FreeFlowApp`'s `MenuBarExtra` label and content both render from `MenuBarPresentation.visual(state:hasError:)`, with the error message shown as a second menu line when present.

## The seam is reusable

`AppState` is the shared observation seam: the deferred recording-indicator HUD ([../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md)) is just another observer of the same `state`, not a new path into the session.

## Related

- [free-flow-session.md](free-flow-session.md) — the UI-agnostic cycle owner whose `state`/`errors` publishers this bridges
- [free-flow-pipeline.md](free-flow-pipeline.md) — where `FreeFlowError` is emitted per stage
- [../decisions/0002-log-redaction-over-debug-flag.md](../decisions/0002-log-redaction-over-debug-flag.md) — why the error message is path-redacted at this boundary
- [../requirements/core-feature.md](../requirements/core-feature.md) — item 5, the visible-feedback requirement this satisfies
- [../conventions/tests.md](../conventions/tests.md) — the `apply` / `visual` test seams
