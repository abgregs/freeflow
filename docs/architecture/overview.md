# Architecture: Overview

Free Flow is a single-target macOS app that lives in the menu bar with no Dock presence (`LSUIElement = true`). It is Apple Silicon only, macOS 14+, distributed as a signed `.app` bundle inside a DMG and a Homebrew cask.

## Process model

One process. SwiftUI owns the `MenuBarExtra` and `Settings` scenes. `AppDelegate` is a thin lifecycle shell that constructs a [`FreeFlowSession`](free-flow-session.md) at launch and calls `start()`. After that, the delegate does not touch managers, does not own the cycle state, and does not handle settings notifications. (The cycle state is projected to the UI through the [`AppState`](app-state-and-menu-bar.md) bridge, which the delegate wires once at launch.)

The composition stack:

```
SwiftUI (MenuBarExtra, Settings)
    │
    ├── observes FreeFlowSession state + errors via AppState
    └── writes settings via @AppStorage  ─┐
                                          │ (also written by SettingsStore)
AppDelegate (lifecycle only)              │
    └── FreeFlowSession                  │
            │   ┌──────────────────────────┘
            │   ▼
            │   SettingsStore  ── publishes per-key value changes
            ▼
        Managers (HotkeyManager, AudioCaptureManager,
                  TextInsertionManager, TranscriptionService)
            │
            ▼
        Capabilities (InputMonitoringCapability, MicrophoneCapability,
                      AccessibilityCapability)
            │
            ▼
        macOS APIs (CGEventTap, AVAudioEngine, CGEvent.post)
```

**Why this layering:** every concern that previously landed in `AppDelegate` (state machine, callback wiring, notification filtering, deferred-restart logic) is now owned by `FreeFlowSession`. Every concern that previously involved calling an OS API "and hoping" (post a synthetic key event, start the audio engine) now goes through a capability that owns both the check and the call. SwiftUI keeps its scene lifecycle; `AppDelegate` shrinks to a few lines.

## Target audience

Free Flow is open-source. Users fall into three groups:

1. **Devs** — clone, run `swift build`, install via `make install` or the bundled script.
2. **Power users** — `brew install --cask abgregs/freeflow/freeflow` (from the `abgregs/homebrew-freeflow` tap).
3. **General users** — download a signed `.dmg` from GitHub Releases, drag to `/Applications`.

The app is **not** distributed via the Mac App Store. **Why:** the App Store sandbox forbids global event taps, which would force a fundamentally different (and worse) architecture for the activation hotkey. See [distribution.md](distribution.md). The capability layer makes a future port less catastrophic — `InputMonitoringCapability` is the seam where a sandbox-safe alternative would substitute.

## The shape of one cycle

Detailed in [free-flow-pipeline.md](free-flow-pipeline.md). The short version, with ownership made explicit:

```
key press → InputMonitoringCapability → HotkeyManager → FreeFlowSession.onActivate
                                                            ↓
                                              state → .recording, MicrophoneCapability
                                                       starts AudioCaptureManager
key release → FreeFlowSession.onDeactivate
                ↓
       state → .processing, TranscriptionService runs,
       AccessibilityCapability posts ⌘V, state → .idle
```

A single `FreeFlowState` enum (`.idle` / `.recording` / `.processing`) gates every transition. `FreeFlowSession` is the only writer. Re-entrant or out-of-order events are no-ops.

## Cross-references

- For the deep module that owns the cycle, see [free-flow-session.md](free-flow-session.md).
- For how the UI observes the cycle without coupling to it, see [app-state-and-menu-bar.md](app-state-and-menu-bar.md).
- For how permission checks are unified with the actions they gate, see [capabilities.md](capabilities.md).
- For the typed settings layer, see [settings-store.md](settings-store.md).
- For the threading constraint that makes the event tap reliable, see [threading-invariant.md](threading-invariant.md).
- For what is configurable at runtime vs. baked in, see [configuration.md](configuration.md).
- For what the user must do at first launch, see [permissions.md](permissions.md).
- For the conventions that govern how this architecture is implemented, see the [conventions/](../conventions/_index.md) folder.
