import Foundation

/// Interprets completed taps into start/stop actions for the two tap activation
/// modes. Pure and clock-injectable so the double-tap timing is unit-testable
/// without a real `CGEventTap` (the reason it's extracted from `HotkeyManager`).
/// `HotkeyManager` owns the trivial key-down→key-up pairing and calls `handleTap`
/// on each completed tap; Hold mode never routes here. See
/// requirements/activation-key-and-mode.md.
@MainActor
final class TapStateMachine {
    enum Action: Equatable { case start, stop, none }

    enum State: Equatable {
        case idle
        case awaitingSecondTap(since: TimeInterval)  // double-tap only
        case recording
    }

    private(set) var state: State = .idle
    private var mode: ActivationMode
    private let windowMs: Int
    private let now: () -> TimeInterval

    init(
        mode: ActivationMode,
        windowMs: Int,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.mode = mode
        self.windowMs = windowMs
        self.now = now
    }

    /// Advances on one completed tap (key-down then key-up) and returns the action
    /// the hotkey should fire.
    func handleTap() -> Action {
        switch mode {
        case .hold:
            return .none  // Hold is handled inline by HotkeyManager, never here.
        case .singleTap:
            if state == .recording {
                state = .idle
                return .stop
            }
            state = .recording
            return .start
        case .doubleTap:
            let t = now()
            switch state {
            case .recording:
                state = .idle
                return .stop
            case .awaitingSecondTap(let since):
                if (t - since) * 1000 <= Double(windowMs) {
                    state = .recording
                    return .start
                }
                // Too slow — this tap becomes the new first tap.
                state = .awaitingSecondTap(since: t)
                return .none
            case .idle:
                state = .awaitingSecondTap(since: t)
                return .none
            }
        }
    }

    /// Adopts a new mode mid-session. Clears a half-finished double-tap detection
    /// but preserves an active `.recording` so a live mode change doesn't strand
    /// the in-flight recording (it must still be stoppable). See
    /// architecture/free-flow-session.md on live-apply.
    func setMode(_ newMode: ActivationMode) {
        mode = newMode
        if state != .recording { state = .idle }
    }

    func reset() {
        state = .idle
    }
}
