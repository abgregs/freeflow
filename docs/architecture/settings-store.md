# Architecture: SettingsStore

`SettingsStore` is the typed read/write/observe seam for everything in `UserDefaults.standard`. SwiftUI still uses `@AppStorage` for bindings; non-SwiftUI consumers use the typed API. Both go through the same backing store, so a write from either side is visible to both.

**Why:** the previous-generation design exposed `UserDefaults.didChangeNotification` directly to observers. That notification fires on every write (including OS-internal writes unrelated to the app), forcing every observer to re-implement the same "read the key, compare to last-applied value, return if unchanged" filter. `SettingsStore` does that filtering once, at the seam, and exposes typed publishers that fire only when a specific key's value actually changes.

## Interface

```swift
struct SettingKey<Value> {
    let name: String
    let defaultValue: Value
}

@MainActor
final class SettingsStore {
    // Read once
    func value<V>(for key: SettingKey<V>) -> V

    // Write (also writes through to UserDefaults.standard so @AppStorage sees it)
    func setValue<V: Equatable>(_ value: V, for key: SettingKey<V>)   // Equatable: skips a no-op write/emit

    // Observe — fires only when the value for this key actually changes
    func publisher<V: Equatable>(for key: SettingKey<V>) -> AnyPublisher<V, Never>
}
```

The set of keys is declared as static members on a dedicated namespace:

```swift
enum Settings {
    static let activationKeyCode = SettingKey<Int>(
        name: "activationKeyCode",
        defaultValue: Int(Constants.defaultActivationKeyCode)
    )
    static let activationMode = SettingKey<ActivationMode>(
        name: "activationMode",
        defaultValue: Constants.defaultActivationMode
    )
    // ...
}
```

(The double-tap detection window is **not** a setting — it's an internal `Constants.doubleTapWindowMs` tunable; see [configuration.md](configuration.md).)

Adding a new setting means adding one static member. Default lives next to the name; no parallel `Constants.defaultX` to drift out of sync.

## How values cross the typed boundary

`SettingsStore` knows how to encode/decode supported types:

- Primitives (`Int`, `String`, `Bool`, `Double`) round-trip directly.
- `RawRepresentable` enums (`ActivationMode`) encode as their raw value.
- `[String]` for the custom dictionary (the key is reserved, consumer-less since the [0008](../planning/0008_custom-dictionary-redesign.md) cut).
- Anything else is a deliberate addition — extend the encode/decode logic in `SettingsStore` itself, not at the call site.

**The benefit:** `FreeFlowSession.subscribeToConfiguration()` looks like this:

```swift
settings.publisher(for: Settings.activationMode)
    .sink { [weak self] newMode in
        self?.applyOrDeferReconfiguration(mode: newMode)
    }
```

No string parsing. No type-cast at the boundary. No comparison-to-last-applied filter — the publisher already de-dupes.

## Coexistence with @AppStorage

SwiftUI Settings UI continues to use `@AppStorage` directly:

```swift
@AppStorage("activationKeyCode") private var activationKeyCode: Int = Int(Constants.defaultActivationKeyCode)
```

This works because `@AppStorage` reads and writes `UserDefaults.standard` directly, and `SettingsStore` does the same. A write from SwiftUI is visible to `SettingsStore` (its publisher fires); a write from `SettingsStore` is visible to SwiftUI (the `@AppStorage` binding updates).

**Rule:** the *key name string* (e.g., `"activationKeyCode"`) appears in exactly two places: the `SettingKey` declaration and the matching `@AppStorage` annotation. They must agree. To prevent drift, expose the name as a single source via the `Settings` namespace:

```swift
@AppStorage(Settings.activationKeyCode.name) private var activationKeyCode: Int = Settings.activationKeyCode.defaultValue
```

This is the only acceptable form. Inline string literals for `UserDefaults` keys outside `Settings.*` declarations are an anti-pattern; see [../conventions/anti-patterns.md](../conventions/anti-patterns.md).

**`@AppStorage` type limit.** `@AppStorage` only binds `Bool` / `Int` / `Double` / `String` / `URL` / `Data` / `RawRepresentable`. A setting whose type it can't represent — notably `[String]` (the custom dictionary, whose UI was cut in [0008](../planning/0008_custom-dictionary-redesign.md) but whose key remains the example) — binds through the typed `SettingsStore` from SwiftUI instead: the view reads `store.value(for:)` and writes `store.setValue(_:for:)`, usually via a small `@Observable` model (the way [`AppState`](app-state-and-menu-bar.md) bridges the session to the menu bar). The "key name in exactly two places" rule still holds for `@AppStorage`-bound keys; a typed-store-bound key simply has no `@AppStorage` annotation and its name lives only in the `SettingKey`.

## What does not belong in SettingsStore

The exclusion list from [../conventions/persistence.md](../conventions/persistence.md) still applies — transcribed text, audio buffers, credentials. `SettingsStore` is for user-tunable settings, not for transient state or sensitive material.

## Testability

`SettingsStore` is initialized with a `UserDefaults` instance. Tests inject `UserDefaults(suiteName: "test-\(UUID().uuidString)")` and tear it down in cleanup. Publishers are observed with synchronous `.sink` collectors for assertions.

```swift
@Test("activationKeyCode publisher fires only on actual change")
func publisherDedupes() async throws {
    let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let store = SettingsStore(backing: defaults)
    var received: [Int] = []
    let token = store.publisher(for: Settings.activationKeyCode).sink { received.append($0) }
    defer { token.cancel(); defaults.removePersistentDomain(forName: ...) }

    store.setValue(54, for: Settings.activationKeyCode)
    store.setValue(54, for: Settings.activationKeyCode)  // no-op
    store.setValue(62, for: Settings.activationKeyCode)

    #expect(received == [54, 62])
}
```

## Related

- [configuration.md](configuration.md) — what runtime-configurable behavior actually exists
- [free-flow-session.md](free-flow-session.md) — the primary non-SwiftUI consumer of settings publishers
- [../conventions/persistence.md](../conventions/persistence.md) — the rules about which storage layer handles what
- [../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md) — the user-facing settings exposed via this store
