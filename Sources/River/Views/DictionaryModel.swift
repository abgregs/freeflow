import Foundation
import Observation

/// Editable view model for the custom dictionary. `[String]` can't bind via
/// `@AppStorage`, so the Settings list reads/writes through the typed
/// `SettingsStore` here — mirroring the `AppState` bridge. Add/delete persist
/// immediately, which fires `Settings.customDictionaryTerms`'s publisher;
/// `AppDelegate` forwards that to `TranscriptionService` (custom-dictionary.md).
@MainActor
@Observable
final class DictionaryModel {
    private(set) var terms: [String]
    @ObservationIgnored private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        self.terms = store.value(for: Settings.customDictionaryTerms)
    }

    // internal for testability — add a trimmed, non-empty, non-duplicate term.
    func add(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !terms.contains(term) else { return }
        terms.append(term)
        persist()
    }

    // internal for testability — delete by row offsets (from SwiftUI `onDelete`).
    // Implemented without SwiftUI's `remove(atOffsets:)` so the model stays
    // testable against Foundation alone.
    func delete(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        terms = terms.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        persist()
    }

    private func persist() {
        store.setValue(terms, for: Settings.customDictionaryTerms)
    }
}
