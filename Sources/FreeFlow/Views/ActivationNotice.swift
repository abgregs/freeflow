import Foundation

/// User-facing copy for an activation-settings change applied *live* during a
/// recording (tap modes only — see architecture/free-flow-session.md). Pure so
/// the copy is unit-tested, mirroring `ActivationKeyOption.capsLockHoldWarning`.
/// `FreeFlowSession` emits these on its `notices` channel; the menu bar (and,
/// later, the recording HUD — planning 0002) display them.
enum ActivationNotice {
    static func keyChanged(toKeyCode code: Int) -> String {
        let label = ActivationKeyOption.all.first { $0.keyCode == code }?.label ?? "the new key"
        return "Activation key changed to \(label). Press it to stop the current recording."
    }

    static func modeChanged(to mode: ActivationMode) -> String {
        "Activation mode changed to \(mode.label). Tap the activation key to stop the current recording."
    }
}
