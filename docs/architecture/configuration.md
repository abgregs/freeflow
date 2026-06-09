# Architecture: Configuration

Two stores. Different responsibilities. Mixing them is the bug.

## `Constants` — compile-time defaults only

`Constants.swift` holds values that are not user-facing and not expected to change at runtime:

- Default values referenced by [`SettingsStore`](settings-store.md) keys (e.g., `defaultActivationKeyCode`, `defaultActivationMode`)
- Internal tunables (e.g., `clipboardRestoreDelay`)
- Identifiers, model lists, hard-coded UI strings

**Rule:** if a user could plausibly want to change it from Settings, it does not live here. Constants is read at startup; nothing observes it. See [../conventions/anti-patterns.md](../conventions/anti-patterns.md).

## `SettingsStore` — runtime configuration

Anything the user can change from Settings flows through [`SettingsStore`](settings-store.md). The store wraps `UserDefaults.standard` behind typed keys and per-key publishers.

Settings keys (the target set; declared progressively as their consumers land — see [planning/milestones.md](../planning/milestones.md)):

| Key | Type | Default | Primary consumer |
|---|---|---|---|
| `activationKeyCode` | `Int` | `Constants.defaultActivationKeyCode` (61, Right Option) | `FreeFlowSession` → `HotkeyManager` |
| `activationMode` | `ActivationMode` | `Constants.defaultActivationMode` (`.hold`) | `FreeFlowSession` → `HotkeyManager` |
| `doubleTapWindowMs` | `Int` | `400` | `HotkeyManager` (`TapStateMachine`) |
| `customDictionaryTerms` | `[String]` | `Constants.defaultDictionaryTerms` | `TranscriptionService` |
| `selectedModel` | `String` | `Constants.defaultModel` | `TranscriptionService` |
| `launchAtLogin` | `Bool` | `false` | `SettingsView` → `SMAppService` |
| `pauseMediaWhileDictating` | `Bool` | `true` | `MediaPauseManager` |

As of M8, `activationKeyCode` (M4), `customDictionaryTerms`, and `launchAtLogin` are declared. The rest land with their consumers: `activationMode` + `doubleTapWindowMs` and `selectedModel` in M9+ (they need the tap behavior, the `ActivationMode` enum + store `RawRepresentable` support, and live model reload), and `pauseMediaWhileDictating` once `MediaPauseManager` exists (deferred — see [../planning/0003_pause-media-while-dictating.md](../planning/0003_pause-media-while-dictating.md)).

SwiftUI binds via `@AppStorage` using the same key names (see [settings-store.md](settings-store.md) for the rule that prevents drift). Non-SwiftUI consumers read via `store.value(for:)` and observe via `store.publisher(for:)`.

## Live apply

Live-apply is a structural property of [`FreeFlowSession`](free-flow-session.md), not a discipline rule.

1. SwiftUI writes a new value through `@AppStorage` (or, equivalently, a programmatic call to `store.setValue(...)`).
2. `SettingsStore.publisher(for: Settings.activationKeyCode)` emits the new typed value (and only when the value actually changed — duplicate writes do not re-emit).
3. The session's subscription receives it on the main actor.
4. The session inspects its own state:
   - If `state == .idle`, it asks `HotkeyManager` to switch immediately. The manager rebuilds the event tap on a fresh `com.freeflow.eventtap` thread (preserving the [threading invariant](threading-invariant.md)).
   - If `state != .idle`, it stores the new value as a pending reconfiguration. On the next return to `.idle` (end of the transcribe/insert task), it applies.

**Why this matters:** the previous-generation design exposed `UserDefaults.didChangeNotification` and required every observer to read keys, compare to last-applied values, and orchestrate deferral. All three steps are gone — typed publishers, structural deferral inside the session, no comparison required.

## Not every setting flows through the session

Only **cycle-timing-sensitive** settings (the activation key/mode → `HotkeyManager`) go through `FreeFlowSession`'s apply-or-defer path, because changing them mid-recording would tear down the event tap. Settings that aren't cycle-timed are wired at the app level instead: `AppDelegate` subscribes `Settings.customDictionaryTerms` and forwards it to `TranscriptionService.setCustomDictionaryTerms` (the dictionary is read at the *next* transcription, so it needs no deferral), and `launchAtLogin` is handled in the Settings view's `onChange` via `SMAppService`. The rule: route a setting through the session only if applying it mid-cycle would corrupt the cycle.

## Restart preserves the threading invariant

When the session asks `HotkeyManager` to switch keys/modes, the manager calls into `InputMonitoringCapability` to stop the current tap (joining the event-tap thread cleanly) and create a new one. The capability always creates the new tap on a fresh `com.freeflow.eventtap` background thread with QoS `.userInteractive`. The threading rule lives in `InputMonitoringCapability` — there is no other path that creates a tap. See [threading-invariant.md](threading-invariant.md).

## Related

- [settings-store.md](settings-store.md) — the typed interface that this section relies on
- [free-flow-session.md](free-flow-session.md) — the consumer of the publishers and owner of the deferral logic
- [../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md) — what these settings mean to the user
- [../conventions/persistence.md](../conventions/persistence.md) — how `UserDefaults` keys are named and consumed
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — compile-time-config-for-user-behavior anti-pattern
