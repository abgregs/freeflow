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
    ├── AppStateTests.swift          # the Combine→Observable UI bridge
    ├── MenuBarPresentationTests.swift  # the pure state→icon/label mapping
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
| `AppState` (Combine→`@Observable` bridge) | Yes | Drive `apply(_:)` directly; assert `state` propagation and that `errorMessage` is path-redacted at the boundary |
| `MenuBarPresentation` mapping | Yes | Pure function; assert icon/label per state and the error-glyph override |
| `Capability` implementations end-to-end | Partial | Inner logic is testable; the OS-call leaf cannot be exercised in CI (no TCC grant) |
| `TranscriptionService` end-to-end | No | Requires WhisperKit model load, real audio, real Whisper run — not a unit test |
| `TextInsertionManager` end-to-end | No | Requires a real Accessibility grant + a real target app for the paste to land |
| `AudioCaptureManager` end-to-end | No | Requires Microphone grant and real audio input |

**Architectural consequence:** the testable inner logic is now the majority of the codebase. `FreeFlowSession` is fully unit-testable through fakes — the cycle (which used to be the bug-hiding wiring) is the test surface. Capability implementations have a small untestable OS-call leaf, but the consuming managers are fully testable against fake capabilities.

## Access seams for tests

Some methods are `internal` (not `private`) specifically so tests can exercise them without going through real OS APIs:

- `HotkeyManager.handle(_:)` / `bindEventStream()` — interpretation and Combine binding seams, exercised by feeding synthetic `TapEvent`s
- `InputMonitoringCapability.decode(_:)` — pure `CGEvent` → `TapEvent` decoder, `nonisolated` so the C tap callback can call it without crossing an actor boundary
- `InputMonitoringCapability.publishForTest(_:)` — pushes a synthetic `TapEvent` into the stream, bypassing the real tap (which requires an Input Monitoring grant on the running process)
- `MicrophoneCapability.publishForTest(_:)` — pushes a synthetic `AVAudioPCMBuffer` into the stream, bypassing the real engine
- `MicrophoneCapability.skipEngineForTesting` — flag that turns `startEngine()` into a no-op. Required because the test runner usually *does* have Microphone permission, so without it the real engine starts and silent audio races with `publishForTest` buffers (M4 got this for free because `tapCreate` returns nil without IM grant; mic capture has no natural skip)
- `AudioCaptureManager.convert(_:from:toSampleRate:)` — pure buffer-list → 16 kHz `[Float]` conversion via `AVAudioConverter`, exercised on synthetic 44.1 kHz buffers
- `TranscriptionService.filterSpecialTokens(_:specialTokenBegin:)` — pure custom-dictionary prompt-token filter; tested on synthetic token lists so the load-bearing "drop everything `>=` `specialTokenBegin`" rule has a regression guard (a single mis-typed `<=` would silently corrupt decoding — `requirements/custom-dictionary.md`)
- `FreeFlowSession.wireHotkeyCallbacks()` — wires `onActivate`/`onDeactivate` without starting the tap, so the chain can be tested end-to-end via `publishForTest`
- `FreeFlowSession.handleActivate()` (sync) / `handleDeactivate()` (async) — state-guarded transitions; tests `await` `handleDeactivate` directly to drive the full `.recording → .processing → .idle` cycle on the test's own timeline, rather than waiting for the Task-wrapped callback the production wiring uses
- `TextInsertionManager.savePasteboard` / `restorePasteboard` — internal for round-trip tests
- `TextInsertionManager.writePasteboard(_:)` — the transcription write path, internal so the 0007 marker test can assert all three nspasteboard.org types ride alongside the string without driving a full `insertText` cycle
- `AccessibilityCapability.skipPostForTesting` — flag that short-circuits both the silent-no-op probe and the real `CGEvent.post`. Required because the test runner's trustedness leaks into the test process, so without it `postKeyEvent` would fire a real paste into whatever app was focused at test time (mirrors `MicrophoneCapability.skipEngineForTesting`)
- `AccessibilityCapability.setStatusForTesting(_:)` — drives `status` (and the `probeConfirmed` cache) synchronously, bypassing `recheck()`'s non-deterministic host TCC read, so a test can lock the `postKeyEvent` gate open or closed
- `AccessibilityCapability.postedEventCountForTesting` — counts the posts that `skipPostForTesting` suppressed, so manager tests assert the capability was asked to post the expected number of events without a real `CGEvent.post`
- `AccessibilityCapability.probe()` — the pure Shift-modifier round-trip detector for the bundle-misidentification silent-no-op case, internal so the round-trip logic has a seam even though its OS-call leaf can't be exercised in CI
- `AccessibilityCapability.classifyFocusedTarget(role:subrole:)` — the pure editable-role table behind the paste guard (planning 0001), tested against a role table (editable / non-editable / unknown-fails-open) with no AX grant; the focused-element read leaf stays untestable in CI
- `AccessibilityCapability.focusedTargetForTesting` — pins the focused-target classification so manager tests never reach the real AX read (the host's live focus at test time would leak into the classification); mirrors `skipPostForTesting`
- `*Capability.map(...)` — the pure status-mapping functions, internal so tests pin the granted/denied/unknown mapping without a real TCC grant
- `FreeFlowSession.configurationApplyCount` / `configurationDeferCount` — internal counters so tests can assert subscription wiring without reaching into the handler closures
- `AppState.apply(_:)` — the two update entry points (`FreeFlowState` and `FreeFlowError`), internal so tests drive observation and the redaction-at-the-boundary choke point without standing up SwiftUI or a live session
- `MenuBarPresentation.visual(state:hasError:)` — pure `state` + error → icon/label mapping, exercised directly so the [core-feature.md](../requirements/core-feature.md) item 5 icon/label contract has a regression guard without a real `MenuBarExtra`
- `ActivationKeyOption.all` / `capsLockHoldWarning(keyCode:mode:)` — the pure activation-key table and the mode-aware Caps Lock/Hold warning predicate, tested so a dropped key or changed warning copy is a failing test, not silent drift (mirrors `MenuBarPresentation`)
- `TranscriptionService.evaluateDictionaryPrompt(wavPath:)` — internal seam for the **A/B eval harness** (`DictionaryEvalTests`): decodes one fixed clip with and without the dictionary prompt, bypassing the empty-fallback, so a recorded clip shows whether the prompt biases or degenerates. The harness is **env-gated** (`.enabled(if: FREEFLOW_AB_WAV)`) so the normal suite skips it; it loads the real model and writes its result to `ab-result.txt`. Used to confirm `small.en` biases where `base.en` empties (`requirements/custom-dictionary.md`)

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
