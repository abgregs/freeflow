import Combine
import Foundation
import Testing
@testable import River

@Suite("SettingsStore")
struct SettingsStoreTests {
    @MainActor
    @Test("round-trips a placeholder key with default")
    func roundTripsWithDefault() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.m1Placeholder) == Settings.m1Placeholder.defaultValue)
        store.setValue(42, for: Settings.m1Placeholder)
        #expect(store.value(for: Settings.m1Placeholder) == 42)
    }

    @MainActor
    @Test("publisher emits only when value changes")
    func publisherDedupes() async throws {
        let store = makeStore()
        var received: [Int] = []
        let token = store.publisher(for: Settings.m1Placeholder).sink { received.append($0) }
        defer { token.cancel() }

        store.setValue(7, for: Settings.m1Placeholder)
        store.setValue(7, for: Settings.m1Placeholder)
        store.setValue(9, for: Settings.m1Placeholder)

        #expect(received == [Settings.m1Placeholder.defaultValue, 7, 9])
    }

    @MainActor
    private func makeStore() -> SettingsStore {
        let suite = "test-\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }
}
