import Foundation

/// The fixed set of keys pickable as the activation key, with their `CGEvent`
/// keycodes, plus the Caps Lock/Hold warning. Pure presentation data extracted
/// from `SettingsView` so the table and the warning rule are unit-tested without
/// SwiftUI (mirrors `MenuBarPresentation`). The human labels and keycodes are
/// the source-of-truth table in requirements/activation-key-and-mode.md.
struct ActivationKeyOption: Identifiable, Equatable {
    let keyCode: Int
    let label: String
    var id: Int { keyCode }

    /// The 10 supported modifier keys, in picker order.
    static let all: [ActivationKeyOption] = [
        .init(keyCode: 62, label: "Right Control"),
        .init(keyCode: 59, label: "Left Control"),
        .init(keyCode: 61, label: "Right Option"),
        .init(keyCode: 58, label: "Left Option"),
        .init(keyCode: 54, label: "Right Command"),
        .init(keyCode: 55, label: "Left Command"),
        .init(keyCode: 60, label: "Right Shift"),
        .init(keyCode: 56, label: "Left Shift"),
        .init(keyCode: 57, label: "Caps Lock"),
        .init(keyCode: 63, label: "Function (Fn)"),
    ]

    /// Caps Lock keycode (`.maskAlphaShift`); Hold mode is unreliable on it.
    static let capsLockKeyCode = 57

    /// Inline warning for the current selection, or `nil`. Fires only for
    /// Caps Lock paired with **Hold** mode — the tap modes work fine on Caps Lock
    /// (they fire on key-up edges). Verbatim copy from
    /// requirements/activation-key-and-mode.md.
    static func capsLockHoldWarning(keyCode: Int, mode: ActivationMode) -> String? {
        keyCode == capsLockKeyCode && mode == .hold
            ? "Caps Lock toggles on press and is unreliable in Hold mode. Switch to Single Tap or Double Tap."
            : nil
    }
}
