import Combine
import Foundation

struct SettingKey<Value> {
    let name: String
    let defaultValue: Value
}

enum Settings {
    static let m1Placeholder = SettingKey<Int>(name: "m1Placeholder", defaultValue: 0)
}

@MainActor
final class SettingsStore {
    private let defaults: UserDefaults
    private var subjects: [String: any SubjectErasing] = [:]
    private var observation: NSKeyValueObservation?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func value<V>(for key: SettingKey<V>) -> V {
        readValue(for: key)
    }

    func setValue<V: Equatable>(_ newValue: V, for key: SettingKey<V>) {
        let current = readValue(for: key)
        writeValue(newValue, for: key)
        if current != newValue {
            (subjects[key.name] as? CurrentValueSubject<V, Never>)?.send(newValue)
        }
    }

    func publisher<V: Equatable>(for key: SettingKey<V>) -> AnyPublisher<V, Never> {
        if let existing = subjects[key.name] as? CurrentValueSubject<V, Never> {
            return existing.removeDuplicates().eraseToAnyPublisher()
        }
        let subject = CurrentValueSubject<V, Never>(readValue(for: key))
        subjects[key.name] = subject
        return subject.removeDuplicates().eraseToAnyPublisher()
    }

    private func readValue<V>(for key: SettingKey<V>) -> V {
        guard defaults.object(forKey: key.name) != nil else { return key.defaultValue }
        if let raw = defaults.object(forKey: key.name) as? V { return raw }
        return key.defaultValue
    }

    private func writeValue<V>(_ value: V, for key: SettingKey<V>) {
        defaults.set(value, forKey: key.name)
    }
}

protocol SubjectErasing: AnyObject {}
extension CurrentValueSubject: SubjectErasing {}
