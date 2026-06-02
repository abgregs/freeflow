# Architecture: FreeFlowSession

`FreeFlowSession` is the deep module that owns one full dictation cycle from activation to text-pasted. It is the single integration point for the four capability-gated managers (hotkey, capture, transcribe, insert), and the only place the `FreeFlowState` machine is observed and mutated.

`AppDelegate` constructs a `FreeFlowSession` at launch and calls `start()`. After that, the delegate is a thin lifecycle shell — it does not touch managers directly and does not own state. **Why:** keeping the integration in one module makes the cycle the unit of test, makes cross-cutting concerns (deferred reconfiguration, state transitions, error recovery) structural rather than scattered, and prevents the class of bug where AppDelegate accumulates orchestration logic over time.

## Interface

```swift
@MainActor
final class FreeFlowSession {
    var state: AnyPublisher<FreeFlowState, Never> { get }   // observable for UI
    var currentState: FreeFlowState { get }                 // sync accessor for tests

    func start() async throws        // begin listening; idempotent
    func stop() async                // tear down cleanly; idempotent
}
```

That's it. There is no `reconfigure(...)` method. **Why:** configuration changes flow in via subscription to [SettingsStore](settings-store.md) publishers inside the session — pushing configuration into the session externally would re-create the leak we're trying to remove.

## What the session owns

1. **The `FreeFlowState` machine** (`.idle` / `.recording` / `.processing`). The session is the only writer; the menu bar and content views observe via the `state` publisher.
2. **The cycle orchestration.** When the hotkey fires `onActivate`, the session transitions to `.recording` and calls the capture module. When `onDeactivate` fires, it stops capture, transitions to `.processing`, runs transcription, posts the paste, and returns to `.idle`.
3. **Deferred reconfiguration.** When a settings change arrives via a SettingsStore publisher during a non-idle state, the session stores it and applies after the cycle completes. This is internal — callers never see it.
4. **Re-entrancy guards.** Activations during `.recording` or `.processing` are no-ops with logging. Out-of-order events are no-ops with logging.

## What the session does not own

- The CGEventTap thread. That's owned by [`InputMonitoringCapability`](capabilities.md), which `HotkeyManager` builds on.
- Whisper model loading. That's owned by `TranscriptionService` and happens on its own schedule.
- Settings storage. That's owned by [`SettingsStore`](settings-store.md). The session subscribes; it does not persist.
- UI. The menu bar and Settings views observe `state`, but the session never reaches into them.

## How it composes

```
              ┌─────────────────────────────────┐
              │       FreeFlowSession          │
              │  ┌─────────────────────────┐    │
              │  │  FreeFlowState machine │    │
              │  └─────────────────────────┘    │
              │  ┌─────────────────────────┐    │
              │  │  pending reconfiguration│    │
              │  └─────────────────────────┘    │
              └──┬──────────┬──────────┬────────┘
                 │          │          │
                 ▼          ▼          ▼
           HotkeyManager  AudioCapture  TextInsertion
                 │             │             │
                 ▼             ▼             ▼
        InputMonitoring   Microphone    Accessibility
           Capability     Capability     Capability
```

`FreeFlowSession` consumes the managers; the managers consume capabilities. No call ever skips a layer.

## Reconfiguration without leaks

When the user changes the activation key or mode in Settings:

1. SwiftUI writes through to `UserDefaults` via `@AppStorage`.
2. `SettingsStore.publisher(for: .activationKeyCode)` emits the new typed value.
3. The session's subscription receives it.
4. If `state == .idle`, the session asks `HotkeyManager` to switch to the new key/mode immediately (which internally rebuilds the event tap on a fresh `com.freeflow.eventtap` thread — see [threading-invariant.md](threading-invariant.md)).
5. If `state != .idle`, the session stores the new value as a pending reconfiguration. On the next return to `.idle` (end of the transcribe/insert task), it applies.

**Why this matters:** in the previous-generation design, `AppDelegate` had to filter `UserDefaults.didChangeNotification`, compare to last-applied values, and orchestrate the deferral. All three steps are gone — typed publishers, structural deferral, no comparison required.

## Testability

The session is the test surface for the cycle. Tests construct a `FreeFlowSession` with stubbed managers (replaced with fakes as each manager gains real behavior in M4–M7) and a `SettingsStore` backed by a per-test `UserDefaults` suite, then drive it with synthetic activations and observe the state publisher:

```swift
@Test("activation during processing is ignored")
func activationDuringProcessingIsIgnored() async throws {
    let fakeHotkey = FakeHotkey()
    let session = FreeFlowSession(/* fakes injected */)
    try await session.start()

    fakeHotkey.fireActivate()
    fakeHotkey.fireDeactivate()
    // now in .processing
    fakeHotkey.fireActivate()  // should be no-op
    #expect(session.currentState == .processing)
}
```

Configuration-subscription wiring is asserted indirectly through internal counters (`configurationApplyCount`, `configurationDeferCount`) — see [../conventions/tests.md](../conventions/tests.md) — so tests confirm the apply-or-defer branch without inspecting handler closures.

`handleActivate` is sync (state changes immediately; audio start is fire-and-forget). `handleDeactivate` is async — tests `await` it directly to drive the full `.recording → .processing → .idle` cycle within the test's own timeline rather than waiting on the Task the production callback wraps it in.

End-to-end tests with real capabilities are integration tests run manually before release; the session's unit tests cover the cycle logic itself.

## Related

- [overview.md](overview.md) — where the session sits in the process model
- [capabilities.md](capabilities.md) — the capability layer the session's managers depend on
- [settings-store.md](settings-store.md) — the typed publishers the session subscribes to
- [free-flow-pipeline.md](free-flow-pipeline.md) — the step-by-step cycle the session implements
- [../conventions/tests.md](../conventions/tests.md) — testing patterns for the session
