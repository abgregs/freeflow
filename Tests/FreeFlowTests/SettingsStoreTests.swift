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
    private func makeStore() -> SettingsStore {
        let suite = "test-\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }
}
