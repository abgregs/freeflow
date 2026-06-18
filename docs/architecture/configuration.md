# Architecture: Configuration

Two stores. Different responsibilities. Mixing them is the bug.

## `Constants` — compile-time defaults only

`Constants.swift` holds values that are not user-facing and not expected to change at runtime:

- Default values referenced by [`SettingsStore`](settings-store.md) keys (e.g., `defaultActivationKeyCode`, `defaultActivationMode`)
- Internal tunables (e.g., `keystrokeChunkUnits`, `doubleTapWindowMs`)
- Identifiers, model lists, hard-coded UI strings

**Rule:** if a user could plausibly want to change it from Settings, it does not live here. Constants is read at startup; nothing observes it. See [../conventions/anti-patterns.md](../conventions/anti-patterns.md).

## Build-variant compile flags (neither store)

A third category is neither a `Constants` value nor a `SettingKey`: the `FREEFLOW_RELEASE` Swift compile condition, set only by the [release pipeline](release-pipeline.md) (`make … SWIFT_FLAGS="-Xswiftc -DFREEFLOW_RELEASE"`). It selects between **build variants** rather than configuring behavior at runtime — its only use today is compiling out the dev-only onboarding Skip button in notarized builds (see [permissions.md](permissions.md)). Reach for a compile flag only when the difference is genuinely build-time (local/self-signed vs. notarized) and must *not* be a runtime toggle; user-facing behavior still belongs in `SettingsStore`.

## `SettingsStore` — runtime configuration

Anything the user can change from Settings flows through [`SettingsStore`](settings-store.md). The store wraps `UserDefaults.standard` behind typed keys and per-key publishers.

Settings keys (the target set; declared progressively as their consumers land — see [planning/milestones.md](../planning/milestones.md)):

| Key | Type | Default | Primary consumer |
|---|---|---|---|
| `activationKeyCode` | `Int` | `Constants.defaultActivationKeyCode` (61, Right Option) | `FreeFlowSession` → `HotkeyManager` |
| `activationMode` | `ActivationMode` | `Constants.defaultActivationMode` (`.hold`) | `FreeFlowSession` → `HotkeyManager` |
| `customDictionaryTerms` | `[String]` | `Constants.defaultDictionaryTerms` | *none in V1 — key reserved for the dictionary redesign ([0008](../planning/0008_custom-dictionary-redesign.md))* |
| `selectedModel` | `String` | `Constants.defaultModel` | `TranscriptionService` |
| `launchAtLogin` | `Bool` | `false` | `SettingsView` → `SMAppService` |
| `pauseMediaWhileDictating` | `Bool` | `true` | `MediaPauseManager` |

As of M9, `activationKeyCode` (M4), `activationMode` (M9), `customDictionaryTerms`, and `launchAtLogin` are declared. `selectedModel` lands with the model picker, and `pauseMediaWhileDictating` once `MediaPauseManager` exists (deferred — see [../planning/0003_pause-media-while-dictating.md](../planning/0003_pause-media-while-dictating.md)). **`doubleTapWindowMs` is deliberately *not* a setting** — it's an internal `Constants` tunable (above) consumed by `HotkeyManager`'s `TapStateMachine`. The user shouldn't have to reason about a double-tap window, so there is no UI control and no slider; a fixed 400 ms is used always.

SwiftUI binds via `@AppStorage` using the same key names (see [settings-store.md](settings-store.md) for the rule that prevents drift). Non-SwiftUI consumers read via `store.value(for:)` and observe via `store.publisher(for:)`.

## Live apply

Live-apply is a structural property of [`FreeFlowSession`](free-flow-session.md), not a discipline rule.

1. SwiftUI writes a new value through `@AppStorage` (or, equivalently, a programmatic call to `store.setValue(...)`).
2. `SettingsStore.publisher(for: Settings.activationKeyCode)` emits the new typed value (and only when the value actually changed — duplicate writes do not re-emit).
3. The session's subscription receives it on the main actor.
4. The session inspects its own state and the active mode:
   - **`.idle`** → `HotkeyManager` reconfigures the hotkey **in place** — it swaps the watched key/mode while the one event tap keeps running (no rebuild; see [threading-invariant.md](threading-invariant.md)).
   - **`.recording` in a tap mode** → the change applies **live, in place**, the recording continues, and the session emits a notice on its `notices` publisher telling the user the new key/mode now stops the recording. Safe precisely because the surviving tap drops no audio.
   - **`.recording` in Hold mode, or `.processing`** → stored as a pending reconfiguration, applied on the next return to `.idle`. Hold defers because the user is physically holding the old key, whose release must stay watched.

**Why this matters:** the previous-generation design exposed `UserDefaults.didChangeNotification` and required every observer to read keys, compare to last-applied values, and orchestrate deferral. All three steps are gone — typed publishers, structural deferral inside the session, no comparison required.

## Not every setting flows through the session

Only **cycle-timing-sensitive** settings (the activation key/mode → `HotkeyManager`) go through `FreeFlowSession`'s apply-or-defer path, because changing them mid-recording would tear down the event tap. Settings that aren't cycle-timed are wired at the app level instead: `launchAtLogin` is handled in the Settings view's `onChange` via `SMAppService`. (`customDictionaryTerms` followed this app-level pattern — `AppDelegate` forwarded it to `TranscriptionService` — until the V1 cut in [0008](../planning/0008_custom-dictionary-redesign.md); the key is declared but currently has no consumer.) The rule: route a setting through the session only if applying it mid-cycle would corrupt the cycle.

## Reconfiguration keeps the one running tap

Switching keys/modes does **not** recreate the event tap. The tap is created once and watches every modifier's `.flagsChanged`; `HotkeyManager` only updates the watched keycode (and the `TapStateMachine` mode) in place. So there is no tap teardown on the live-apply path — which is exactly why a mid-recording change drops no audio. The only code that ever calls `CGEvent.tapCreate` is `InputMonitoringCapability`, once at startup. See [threading-invariant.md](threading-invariant.md).

## Related

- [settings-store.md](settings-store.md) — the typed interface that this section relies on
- [free-flow-session.md](free-flow-session.md) — the consumer of the publishers and owner of the deferral logic
- [../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md) — what these settings mean to the user
- [../conventions/persistence.md](../conventions/persistence.md) — how `UserDefaults` keys are named and consumed
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — compile-time-config-for-user-behavior anti-pattern
