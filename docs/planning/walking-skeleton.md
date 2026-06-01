# Planning: Walking Skeleton (M1)

The first milestone. Smallest possible app that exercises the full build/sign/install/launch pipeline **and** lays down the architectural skeleton that M2–M9 fill in. **No feature code.**

## Why this comes first

Two classes of past failures motivate doing infrastructure and skeleton first:

1. **Infrastructure failures** — malformed `.app` bundle (missing `Info.plist`), incomplete signing flow (missing entitlements at sign time), unclear path between "I cloned and ran `swift build`" and "the app actually works." All three are invisible until you try to use the app for something real.
2. **Composition failures** — managers grew piecemeal, accreted into `AppDelegate`, and the cycle wiring became where bugs hid. Laying down `RiverSession` / `Capability` / `SettingsStore` as empty stubs in M1 means M2–M9 fill in the interiors instead of inventing new top-level structure.

Doing both first — and confirming they work before writing any logic — prevents discovering them three milestones in, when the bug surface includes both the infrastructure problem and whatever feature you happened to be testing.

## Deliverable

A working `/Applications/River.app` with:

- A menu bar icon (any SF Symbol — `mic` is the obvious choice).
- A menu dropdown with two items: "Settings…" and "Quit River".
- A Settings window (empty `Form` with one section: "About" showing the app version).
- An onboarding window that opens on first launch with placeholder text ("Permissions setup will live here").
- Skeleton stubs for the architectural modules (see below).

No audio. No hotkey. No transcription. No real permission checks.

## Acceptance criteria

1. **`swift build` succeeds** on macOS 14+ with only CommandLineTools installed (no full Xcode required).
2. **`make install`** (or equivalent) produces `/Applications/River.app`:
   - With `Contents/Info.plist` containing `CFBundleIdentifier=com.river.app`, `LSUIElement=true`, `CFBundleName=River`, `CFBundleVersion`, `CFBundleShortVersionString`, `NSMicrophoneUsageDescription`.
   - Signed with the "River Dev" identity (`codesign -dv` reports `Identifier=com.river.app`).
   - With entitlements applied (`codesign -d --entitlements -` shows `com.apple.security.app-sandbox = false`).
3. **`open /Applications/River.app`** launches:
   - The app appears in the menu bar (no Dock icon).
   - The menu opens on click and shows the two items.
   - "Settings…" opens a window.
   - "Quit River" terminates the app.
4. **`swift test`** runs and passes. Required tests at this milestone:
   - `RiverSession.start()` transitions state from `.idle` to `.idle` (no-op cycle works).
   - `SettingsStore` round-trips a placeholder key.
   - Each `Capability` returns `.unknown` for status (real checks land in M2).
5. **The README** documents the one-time setup of the "River Dev" code-signing certificate (Keychain Access → Certificate Assistant → Create a Certificate → Self Signed Root → Code Signing → name "River Dev").

## Architectural skeleton landed in M1

These are stubs — empty implementations conforming to the protocols documented in `docs/architecture/`. M2 onward fills them in. The point is that the top-level shape is correct from day one:

```
App/
  RiverApp.swift           // @main, MenuBarExtra + Settings scenes
  AppDelegate.swift            // constructs RiverSession, calls start()
Architecture/
  RiverSession.swift       // owns RiverState, holds (stub) managers
  SettingsStore.swift          // typed read/write/observe wrapper around UserDefaults
  Capability.swift             // protocol declaration
  AccessibilityCapability.swift     // status: .unknown; recheck() no-op
  MicrophoneCapability.swift        // status: .unknown; recheck() no-op
  InputMonitoringCapability.swift   // status: .unknown; recheck() no-op
Managers/
  HotkeyManager.swift          // empty stub, takes InputMonitoringCapability via init
  AudioCaptureManager.swift    // empty stub, takes MicrophoneCapability via init
  TextInsertionManager.swift   // empty stub, takes AccessibilityCapability via init
  TranscriptionService.swift   // empty stub
Models/
  RiverState.swift         // enum { idle, recording, processing }
Views/
  OnboardingView.swift         // iterates capability set, placeholder rows
  SettingsView.swift           // empty Form
Utilities/
  Constants.swift              // defaults referenced by Settings keys
Resources/
  Info.plist
  River.entitlements
```

## What this milestone *does not* do

- Doesn't request any permissions (capabilities all return `.unknown`).
- Doesn't load WhisperKit.
- Doesn't create an event tap.
- Doesn't capture audio.
- Doesn't paste anything.
- Doesn't subscribe to real settings publishers (the `Settings` namespace is mostly empty).

If at the end of M1 you can't install, launch, and quit the app cleanly via the menu, **stop and fix that before starting M2**. None of the feature milestones work without this foundation.

## Architectural decisions made during M1

These are decisions the walking skeleton makes that subsequent milestones inherit:

- **Build system**: `swift build` + a small Makefile that wraps bundle assembly. Don't use `xcodebuild` for local installs — it forces a full Xcode dependency on contributors. (Use `xcodebuild` for release builds in M11.)
- **Test framework**: `swift-testing` (`import Testing`), not XCTest. See [../conventions/tests.md](../conventions/tests.md).
- **Folder layout**: matches the skeleton above. Even with empty placeholders.
- **Logging subsystem**: `com.river.app`. First category: `app`. See [../conventions/logging.md](../conventions/logging.md).
- **Composition direction**: `RiverApp` → `AppDelegate` → `RiverSession` → Managers → Capabilities → OS. No layer skips.
- **Onboarding window presentation**: `AppDelegate` owns an `NSWindow` whose `contentViewController` is `NSHostingController(rootView: OnboardingView(...))`. **Why:** SwiftUI's `Window` scene does not auto-present in `LSUIElement = true` apps — declaring it does nothing until something calls `openWindow`. AppKit's `NSWindow.makeKeyAndOrderFront` is the only reliable trigger from `applicationDidFinishLaunching`. The gate is `capabilities.contains { $0.currentStatus != .granted }`.
- **Settings window presentation**: opened via `@Environment(\.openSettings)` (macOS 14+) from a SwiftUI view inside `MenuBarExtra`. **Why:** the legacy `NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)` selector silently no-ops for `LSUIElement` apps. The environment value is the supported path.
- **`Settings.m1Placeholder`**: a single throwaway `SettingKey<Int>` declared on the `Settings` namespace so the M1 round-trip test has something to exercise. Removed in M4 when `Settings.activationKeyCode` landed.

## Related

- [milestones.md](milestones.md) — the rest of the roadmap
- [../architecture/river-session.md](../architecture/river-session.md) — the module this milestone stubs out
- [../architecture/capabilities.md](../architecture/capabilities.md) — the capability layer this milestone declares
- [../architecture/settings-store.md](../architecture/settings-store.md) — the typed settings layer this milestone declares
- [../architecture/distribution.md](../architecture/distribution.md) — full distribution story, of which M1 is the local-dev piece
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — the bundle-metadata anti-pattern this milestone exists to prevent
