import Combine
import Foundation
import Testing
@testable import FreeFlow

@Suite("SettingsStore")
struct SettingsStoreTests {
    @MainActor
    @Test("round-trips activationKeyCode with default")
    func roundTripsWithDefault() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.activationKeyCode) == Settings.activationKeyCode.defaultValue)
        store.setValue(42, for: Settings.activationKeyCode)
        #expect(store.value(for: Settings.activationKeyCode) == 42)
    }

    @MainActor
    @Test("publisher emits only when value changes")
    func publisherDedupes() async throws {
        let store = makeStore()
        var received: [Int] = []
        let token = store.publisher(for: Settings.activationKeyCode).sink { received.append($0) }
        defer { token.cancel() }

        store.setValue(7, for: Settings.activationKeyCode)
        store.setValue(7, for: Settings.activationKeyCode)
        store.setValue(9, for: Settings.activationKeyCode)

        #expect(received == [Settings.activationKeyCode.defaultValue, 7, 9])
    }

    @MainActor
    @Test("round-trips [String] and Bool settings")
    func roundTripsCollectionAndBool() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.customDictionaryTerms) == [])
        store.setValue(["Swift", "WhisperKit"], for: Settings.customDictionaryTerms)
        #expect(store.value(for: Settings.customDictionaryTerms) == ["Swift", "WhisperKit"])

        #expect(store.value(for: Settings.launchAtLogin) == false)
        store.setValue(true, for: Settings.launchAtLogin)
        #expect(store.value(for: Settings.launchAtLogin) == true)
    }

    @MainActor
    @Test("round-trips a RawRepresentable enum (ActivationMode) as its raw value")
    func roundTripsActivationMode() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.activationMode) == .hold)  // default
        store.setValue(ActivationMode.doubleTap, for: Settings.activationMode)
        #expect(store.value(for: Settings.activationMode) == .doubleTap)
    }

    @MainActor
    @Test("activationMode publisher dedupes; an @AppStorage-style raw write reaches it as the enum")
    func activationModePublisher() async throws {
        // SwiftUI's @AppStorage writes the *raw string* straight to UserDefaults.
        // The store must decode it back to ActivationMode and emit it, or the
        // session never hears a mode change from the UI (the M8 bridge bug class).
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        var received: [ActivationMode] = []
        let token = store.publisher(for: Settings.activationMode).sink { received.append($0) }
        defer { token.cancel() }

        store.setValue(ActivationMode.singleTap, for: Settings.activationMode)
        store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // no-op
        defaults.set(ActivationMode.doubleTap.rawValue, forKey: Settings.activationMode.name)  // bypasses setValue
        await waitUntil { received.last == .doubleTap }

        #expect(received == [.hold, .singleTap, .doubleTap])
    }

    @MainActor
    @Test("an external UserDefaults write (like @AppStorage) reaches the publisher")
    func externalWriteReachesPublisher() async throws {
        // The load-bearing M8 path: SwiftUI `@AppStorage` writes straight to
        // UserDefaults, bypassing `setValue`. If the store doesn't bridge that into
        // its publisher, `FreeFlowSession` never hears a settings change from the UI
        // and live-apply silently breaks — the exact gap this regression guards.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        var received: [Int] = []
        let token = store.publisher(for: Settings.activationKeyCode).sink { received.append($0) }
        defer { token.cancel() }

        defaults.set(99, forKey: Settings.activationKeyCode.name)   // bypasses setValue
        await waitUntil { received.last == 99 }
        #expect(received.last == 99)
    }

    @MainActor
    @Test("a stored value that is neither castable nor DefaultsConvertible falls back to the default")
    func undecodableStoredValueFallsBackToDefault() async throws {
        // Defensive: if some other process (or a schema change) leaves a value of
        // the wrong type under a key, `readValue` must return the typed default,
        // not trap. `activationKeyCode` is an `Int` (not `DefaultsConvertible`), so
        // a stored `String` is neither directly castable nor decodable — the
        // last-resort `return key.defaultValue` path.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("not an int", forKey: Settings.activationKeyCode.name)
        let store = SettingsStore(defaults: defaults)
        #expect(store.value(for: Settings.activationKeyCode) == Settings.activationKeyCode.defaultValue)
    }

    @MainActor
    private func makeStore() -> SettingsStore {
        let suite = "test-\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)   // up to ~1s total
        }
    }
}
