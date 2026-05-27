# Conventions: Persistence

`UserDefaults.standard` is the only persistence layer. No on-disk JSON, no SQLite, no Keychain (yet — see future-considerations at the bottom).

Access to `UserDefaults.standard` goes through [`SettingsStore`](../architecture/settings-store.md) for non-SwiftUI consumers, and through `@AppStorage(Settings.x.name)` for SwiftUI. Both write through to the same underlying defaults; both observe correctly.

## Declaring a setting

Every setting is declared once on the `Settings` namespace:

```swift
enum Settings {
    static let activationKeyCode = SettingKey<Int>(
        name: "activationKeyCode",
        defaultValue: Int(Constants.defaultActivationKeyCode)
    )
    static let activationMode = SettingKey<ActivationMode>(
        name: "activationMode",
        defaultValue: .hold
    )
    // ...
}
```

Rules:

- **Name:** lowerCamelCase, matches the property name. Short but descriptive. `doubleTapWindowMs` is better than `dtw` and better than `doubleTapDetectionWindowInMilliseconds`.
- **No prefixes.** `UserDefaults.standard` is already namespaced to the bundle ID.
- **Default:** sourced from `Constants` for defaults that have semantic meaning (e.g., `defaultActivationKeyCode`); inline for simple values.
- **One declaration only.** The string `"activationKeyCode"` appears in exactly one place in the codebase: the `SettingKey` declaration. SwiftUI references it via `Settings.activationKeyCode.name`. See [anti-patterns.md](anti-patterns.md) item #8.

## Reading

Two patterns. Both safe.

1. **SwiftUI binding** (most user-facing settings):

   ```swift
   @AppStorage(Settings.activationKeyCode.name)
   private var activationKeyCode: Int = Settings.activationKeyCode.defaultValue
   ```

   `@AppStorage` reads from `UserDefaults.standard` and re-renders on change.

2. **Typed read for non-SwiftUI consumers:**

   ```swift
   let mode = store.value(for: Settings.activationMode)   // ActivationMode
   ```

The `store.value(for:)` call returns the typed value with the default applied if the key is unset. There is no third pattern.

Note: `@AppStorage` does not support `CGKeyCode` (a `UInt32` typealias). Store as `Int` and cast at use sites — `Settings.activationKeyCode.defaultValue` is already an `Int`.

## Writing

- SwiftUI writes via `@AppStorage` bindings — happens automatically when the user picks something in Settings.
- Programmatic writes go through `store.setValue(_:for:)`. When they happen, log them at `.info`. **Why:** unexplained settings changes are confusing to debug.

## Observation

Subscribe to typed per-key publishers:

```swift
store.publisher(for: Settings.activationMode)
    .sink { newMode in
        // newMode is ActivationMode; publisher fires only when the value actually changes
    }
```

There is no need to filter `UserDefaults.didChangeNotification` manually. The store does that filtering at the seam — publishers fire only when their specific key's value changes. See [../architecture/settings-store.md](../architecture/settings-store.md).

## What does **not** go in UserDefaults

- Transcribed text (transient, sensitive).
- Audio buffers (transient, large).
- Anything WhisperKit caches itself (it manages its own model storage).
- API keys or credentials. **Why:** UserDefaults is plaintext and inspectable via `defaults read`. Use Keychain when this becomes relevant (future).

## Future considerations

If the app ever needs to store credentials (e.g., a paid speech-to-text fallback), use `Keychain` via `SecItem*` APIs. Document the key schema here.

If the app ever needs structured user data beyond settings (history, sessions), evaluate moving to `SwiftData` or a small SQLite store. Don't shoehorn collections of dictionaries into `UserDefaults`.

## Related

- [../architecture/settings-store.md](../architecture/settings-store.md) — the typed API this convention relies on
- [../architecture/configuration.md](../architecture/configuration.md) — the live-apply contract
- [../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md) — which settings the app actually exposes
- [anti-patterns.md](anti-patterns.md) — item #8 on inline key string literals
