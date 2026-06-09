import Foundation
import Testing
@testable import FreeFlow

@Suite("DictionaryModel")
struct DictionaryModelTests {
    @MainActor
    @Test("add trims whitespace and ignores empty + duplicate terms")
    func addNormalizes() {
        let model = makeModel()
        model.add("  GitHub  ")
        model.add("GitHub")   // duplicate
        model.add("   ")      // empty after trim
        #expect(model.terms == ["GitHub"])
    }

    @MainActor
    @Test("delete removes the addressed rows")
    func deleteRemoves() {
        let model = makeModel()
        model.add("a"); model.add("b"); model.add("c")
        model.delete(at: IndexSet(integer: 1))
        #expect(model.terms == ["a", "c"])
    }

    @MainActor
    @Test("remove deletes a specific term by value and persists")
    func removeByValue() {
        let store = makeStore()
        let model = DictionaryModel(store: store)
        model.add("a"); model.add("b"); model.add("c")
        model.remove("b")
        #expect(model.terms == ["a", "c"])
        #expect(DictionaryModel(store: store).terms == ["a", "c"])   // persisted
    }

    @MainActor
    @Test("edits persist through the store so a reload sees them")
    func editsPersist() {
        // The add must write through the store — that's what fires the publisher
        // AppDelegate forwards to TranscriptionService. A fresh model proves it.
        let store = makeStore()
        DictionaryModel(store: store).add("Kubernetes")
        #expect(DictionaryModel(store: store).terms == ["Kubernetes"])
        #expect(store.value(for: Settings.customDictionaryTerms) == ["Kubernetes"])
    }

    @MainActor private func makeStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @MainActor private func makeModel() -> DictionaryModel {
        DictionaryModel(store: makeStore())
    }
}
