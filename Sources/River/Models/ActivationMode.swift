import Foundation

/// How the activation key starts and stops a recording. Persisted via
/// `Settings.activationMode` (raw value) and interpreted by `HotkeyManager` —
/// Hold inline, the two tap modes through `TapStateMachine`. See
/// requirements/activation-key-and-mode.md.
enum ActivationMode: String, CaseIterable, Identifiable {
    case hold
    case singleTap
    case doubleTap

    var id: String { rawValue }

    /// Human-readable name for the Settings picker.
    var label: String {
        switch self {
        case .hold: return "Hold"
        case .singleTap: return "Single Tap"
        case .doubleTap: return "Double Tap"
        }
    }

    /// One-line behavior summary shown under the picker.
    var description: String {
        switch self {
        case .hold: return "Hold the key while speaking; release to finish."
        case .singleTap: return "Tap to start recording; tap again to finish."
        case .doubleTap: return "Double-tap to start; a single tap finishes."
        }
    }
}
