# Conventions: Tests

Use **swift-testing** (the newer framework, `import Testing`, `@Test`, `#expect`), not XCTest. **Why:** swift-testing runs on the toolchain that ships with CommandLineTools — `swift test` works without a full Xcode.app install. XCTest requires the XCTest.framework that only ships with Xcode, which silently excludes contributors who don't have it installed.

## Layout

```
Tests/
└── FreeFlowTests/
    ├── FreeFlowSessionTests.swift
    ├── HotkeyManagerTests.swift
    ├── TapStateMachineTests.swift
    ├── SettingsStoreTests.swift
    ├── CapabilityTests.swift        # the capability layer, grouped (see below)
    └── ...
```

One test file per primary type under test, with one exception: the **capability layer is grouped into `CapabilityTests.swift`**, whose `@Suite`s span the `Capability` protocol, `OnboardingGate`, and the three capability implementations. Their per-type surfaces are small and share one `FakeCapability`, so a single file is clearer than five near-empty ones. Suite names mirror the type or concern:

```swift
import Testing
@testable import FreeFlow

@Suite("FreeFlowSession")
struct FreeFlowSessionTests {
    @Test("activation while idle starts recording")
    func activationWhileIdleStartsRecording() async throws {
        // ...
        #expect(session.currentState == .recording)
    }
}
```

## What is and isn't testable

| Component | Testable? | How |
|---|---|---|
| `FreeFlowSession` (cycle logic) | Yes, fully | Inject fakes for the four managers + a fake `SettingsStore`; drive synthetic activations; observe state publisher |
| `TapStateMachine` | Yes | Pure state machine with injectable clock; feed synthetic key events |
| `HotkeyManager` event interpretation | Yes | Synthesize `CGEvent`s, feed directly into internal helpers; uses a fake `InputMonitoringCapability` so no real tap is created |
| `SettingsStore` | Yes | Inject `UserDefaults(suiteName:)`; assert publisher emissions; assert dedupe behavior |
| `Capability` consumers (managers) | Yes | Inject fake capabilities; assert capability methods are called; assert typed errors propagate |
| `Capability` implementations end-to-end | Partial | Inner logic is testable; the OS-call leaf cannot be exercised in CI (no TCC grant) |
| `TranscriptionService` end-to-end | No | Requires WhisperKit model load, real audio, real Whisper run — not a unit test |
| `TextInsertionManager` end-to-end | No | Requires a real Accessibility grant + a real target app for the paste to land |
| `AudioCaptureManager` end-to-end | No | Requires Microphone grant and real audio input |

**Architectural consequence:** the testable inner logic is now the majority of the codebase. `FreeFlowSession` is fully unit-testable through fakes — the cycle (which used to be the bug-hiding wiring) is the test surface. Capability implementations have a small untestable OS-call leaf, but the consuming managers are fully testable against fake capabilities.

## Access seams for tests

Some methods are `internal` (not `private`) specifically so tests can exercise them without going through real OS APIs:

- `HotkeyManager` event-interpretation helpers — internal for synthetic-event tests
- `InputMonitoringCapability` event-decoding helpers — internal for synthetic-event tests
- `TextInsertionManager.savePasteboard` / `restorePasteboard` — internal for round-trip tests
- `*Capability.map(...)` — the pure status-mapping functions, internal so tests pin the granted/denied/unknown mapping without a real TCC grant

Mark them clearly:

```swift
// internal for testability (CGEventTap cannot be created in CI)
func decodeFlagsChanged(_ event: CGEvent) -> ActivationEdge? { ... }
```

**Do not promote these to `public`.** Internal is enough; public is an API contract.

## Fake capabilities

Capabilities are `final` and own real OS calls, so fakes conform to the `Capability` **protocol** rather than subclassing a concrete type. A single `FakeCapability` covers status, onboarding, and gate tests:

```swift
@MainActor
final class FakeCapability: Capability {
    let displayName: String
    let setupInstructions: String?
    private let subject: CurrentValueSubject<CapabilityStatus, Never>
    private(set) var requestGrantCount = 0

    init(displayName: String = "Fake", setupInstructions: String? = nil, status: CapabilityStatus = .denied) {
        self.displayName = displayName
        self.setupInstructions = setupInstructions
        self.subject = CurrentValueSubject(status)
    }

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }
    func set(_ status: CapabilityStatus) { subject.send(status) }   // drive transitions in tests
    func recheck() async {}
    func requestGrant() async { requestGrantCount += 1 }
    func openSystemSettings() {}
}
```

Tests substitute these into `OnboardingGate`, managers, and `FreeFlowSession` to exercise scenarios (denied, unknown, grants late) without OS interaction. An action-specific manager test can use a purpose-built protocol-conforming fake that records calls (e.g. posted events for `TextInsertionManager`).

## Test isolation

- Tests that touch `UserDefaults` directly must use a per-test suite name:
  ```swift
  let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
  defer { defaults.removePersistentDomain(forName: ...) }
  ```
  Most tests will use a fake `SettingsStore` instead and avoid `UserDefaults` entirely.
- Tests must not depend on test execution order.
- Tests must not require network, microphone, or accessibility permissions.

## Running

```bash
swift test                                       # all tests
swift test --filter FreeFlowSessionTests        # one suite
swift test --filter "activation while idle"      # one test
```

If a test requires a permission or external resource and can't be made hermetic, mark it `.disabled` with a reason and document the gap in `docs/planning/_index.md`:

```swift
@Test(.disabled("requires accessibility grant; run manually before release"))
func endToEndPaste() { ... }
```

## Related

- [swift-style.md](swift-style.md) — the access-control rules that enable test seams
- [../architecture/free-flow-session.md](../architecture/free-flow-session.md) — the session is the primary integration test surface
- [../architecture/capabilities.md](../architecture/capabilities.md) — the capability layer that makes managers testable against fakes
- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — why the real event tap is integration-tested via synthetic events, not unit-tested
