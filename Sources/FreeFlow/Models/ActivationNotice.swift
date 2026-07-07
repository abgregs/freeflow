import Foundation

/// User-facing copy for recording-context notices: an activation-settings change
/// applied *live* during a recording (tap modes only — see
/// architecture/free-flow-session.md), and a canceled recording (planning 0017).
/// Pure so the copy is unit-tested, mirroring `ActivationKeyOption.capsLockHoldWarning`.
/// `FreeFlowSession` emits these on its `notices` channel; the menu bar and the
/// recording HUD (planning 0002) display them.
enum ActivationNotice {
    static func keyChanged(toKeyCode code: Int) -> String {
        let label = ActivationKeyOption.all.first { $0.keyCode == code }?.label ?? "the new key"
        return "Activation key changed to \(label). Press it to stop the current recording."
    }

    static func modeChanged(to mode: ActivationMode) -> String {
        "Activation mode changed to \(mode.label). Tap the activation key to stop the current recording."
    }

    // The recording was discarded via the cancel gesture or the menu item — no
    // transcription, no paste (planning 0017 AC1). Surfaced so the cancel is
    // visible, not silent.
    static let recordingCanceled = "Recording canceled."
}
