import Combine
import Foundation

struct SettingKey<Value> {
    let name: String
    let defaultValue: Value
}

enum Settings {
    static let activationKeyCode = SettingKey<Int>(
        name: "activationKeyCode",
        defaultValue: Constants.defaultActivationKeyCode
    )
    static let activationMode = SettingKey<ActivationMode>(
        name: "activationMode",
        defaultValue: Constants.defaultActivationMode
    )
    static let customDictionaryTerms = SettingKey<[String]>(
        name: "customDictionaryTerms",
        defaultValue: Constants.defaultDictionaryTerms
    )
    static let launchAtLogin = SettingKey<Bool>(
        name: "launchAtLogin",
        defaultValue: false
    )
    static let selectedModel = SettingKey<String>(
        name: "selectedModel",
        defaultValue: Constants.defaultModel
    )
    // Play a short system sound on recording start and stop (planning 0016).
    // Default on — matches the macOS built-in dictation affordance.
    static let playFeedbackSounds = SettingKey<Bool>(
        name: "playFeedbackSounds",
        defaultValue: true
    )
    // Pause now-playing media when dictation starts; resume when the cycle ends
    // (planning 0003). Default on — most users dictating over music want this.
    // Consumer: MediaPauseManager (see architecture/configuration.md).
    static let pauseMediaWhileDictating = SettingKey<Bool>(
        name: "pauseMediaWhileDictating",
        defaultValue: true
    )
}

@MainActor
final class SettingsStore {
    private let defaults: UserDefaults
    private var subjects: [String: any SubjectErasing] = [:]
    private var reReaders: [String: () -> Void] = [:]
    private var defaultsObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
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
        // Re-read this key whenever UserDefaults changes out from under us — e.g.
        // a SwiftUI `@AppStorage` write, which doesn't go through `setValue`.
        reReaders[key.name] = { [weak self, weak subject] in
            guard let self, let subject else { return }
            subject.send(self.readValue(for: key))
        }
        startObservingIfNeeded()
        return subject.removeDuplicates().eraseToAnyPublisher()
    }

    // Bridges external `UserDefaults` writes (notably SwiftUI `@AppStorage`, which
    // bypasses `setValue`) into the per-key subjects. The store is the single seam
    // that filters: `removeDuplicates()` downstream means an unrelated key's write
    // is a no-op for this publisher (settings-store.md). Without this, a settings
    // change from the UI would never reach `FreeFlowSession`.
    private func startObservingIfNeeded() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reReadAll() }
        }
    }

    private func reReadAll() {
        for reRead in reReaders.values { reRead() }
    }

    private func readValue<V>(for key: SettingKey<V>) -> V {
        guard let stored = defaults.object(forKey: key.name) else { return key.defaultValue }
        if let direct = stored as? V { return direct }
        // Types that persist as something other than themselves (RawRepresentable
        // enums store their raw value) decode here. Primitives and [String] take
        // the direct path above. See settings-store.md.
        if let convertible = V.self as? any DefaultsConvertible.Type,
           let value = convertible.fromDefaults(stored) as? V {
            return value
        }
        return key.defaultValue
    }

    private func writeValue<V>(_ value: V, for key: SettingKey<V>) {
        if let convertible = value as? any DefaultsConvertible {
            defaults.set(convertible.asDefaults, forKey: key.name)
        } else {
            defaults.set(value, forKey: key.name)
        }
    }
}

protocol SubjectErasing: AnyObject {}
extension CurrentValueSubject: SubjectErasing {}

// How a non-primitive setting crosses the UserDefaults boundary. RawRepresentable
// enums persist as their raw value; extend this here (not at the call site) for
// any future type UserDefaults can't store directly. See settings-store.md.
protocol DefaultsConvertible {
    static func fromDefaults(_ stored: Any) -> Self?
    var asDefaults: Any { get }
}

extension DefaultsConvertible where Self: RawRepresentable {
    static func fromDefaults(_ stored: Any) -> Self? {
        (stored as? RawValue).flatMap(Self.init(rawValue:))
    }
    var asDefaults: Any { rawValue }
}

extension ActivationMode: DefaultsConvertible {}
