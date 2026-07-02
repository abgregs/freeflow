# AGENTS.md

Project: **Free Flow** — a macOS menu bar dictation app. macOS 14+, Apple Silicon, on-device transcription via WhisperKit.

## Working in this repo

Authoritative project context lives in [`docs/`](docs/_index.md). Read `docs/_index.md` first to get the map. Active work is tracked in [`docs/planning/current-focus.md`](docs/planning/current-focus.md).

**Before any non-trivial code change:** surface the applicable conventions, architectural constraints, and active requirements from `docs/`.

**After any non-trivial code change:** doc updates alongside your change are welcome, not required — doc/code drift is caught by the maintainer's automated daily doc sync ([docs/conventions/doc-maintenance.md](docs/conventions/doc-maintenance.md)).

## Build & run

```bash
swift build              # debug build
swift test               # run all tests (uses swift-testing, not XCTest)
make install             # release build → bundle → sign → install to /Applications
```

Only the Xcode Command Line Tools are required — no full Xcode. The `make install` step requires a one-time self-signed code-signing certificate named "Free Flow Dev" in the login keychain. See [docs/architecture/distribution.md](docs/architecture/distribution.md).

## Architectural shape

Three deep modules carry most of the design:

- **[`FreeFlowSession`](docs/architecture/free-flow-session.md)** owns one full activation-to-paste cycle. `AppDelegate` is a thin lifecycle shell that constructs the session and calls `start()`. The state machine, callback wiring, and deferred-reconfiguration logic all live inside the session — nowhere else.
- **[`Capability`](docs/architecture/capabilities.md)** layer owns each macOS permission: both the TCC check and the OS call that the permission gates. `CGEvent.post` is only called inside `AccessibilityCapability`; `AVAudioEngine.start()` is only called inside `MicrophoneCapability`; `CGEvent.tapCreate` is only called inside `InputMonitoringCapability`.
- **[`SettingsStore`](docs/architecture/settings-store.md)** wraps `UserDefaults.standard` behind typed per-key publishers. SwiftUI uses `@AppStorage(Settings.x.name)`; non-SwiftUI code uses `store.publisher(for: Settings.x)`.

Read the three docs above before adding code that touches the cycle, a permission, or a setting.

## Load-bearing rules that must not regress

1. **Event tap thread invariant** — owned by `InputMonitoringCapability`. The CFRunLoop runs on a dedicated `com.freeflow.eventtap` background thread with QoS `.userInteractive`. Never on the main run loop. See [docs/architecture/threading-invariant.md](docs/architecture/threading-invariant.md).
2. **Bundle integrity** — `Info.plist` and `--entitlements` are mandatory at sign time. `AccessibilityCapability` includes a silent-no-op detector for the bundle-misidentification failure mode, but do not rely on the detector to mask a malformed bundle. See [docs/conventions/anti-patterns.md](docs/conventions/anti-patterns.md) item #3.
3. **One source of truth for OS API calls.** `CGEvent.post`, `AVAudioEngine.start`, and `CGEvent.tapCreate` are each called in exactly one place — the corresponding capability. Adding a second call site defeats the design.
4. **One source of truth for `UserDefaults` key strings.** Each key appears in exactly one `SettingKey` declaration. `@AppStorage` references it via `Settings.x.name`. Inline string literals are a regression. See [docs/conventions/anti-patterns.md](docs/conventions/anti-patterns.md) item #8.
5. **Compile-time vs. runtime config** — user-facing settings live in `SettingsStore` from day 1, not in `Constants.swift`. `Constants` holds defaults that `Settings` keys reference, plus internal tunables.

The previous-generation app's worst bugs (silent paste failure, mid-recording state corruption, lying permission checks, onboarding too late) became *structurally impossible* under this architecture — not via discipline, but because there is no code path that can produce them. Keep it that way.
