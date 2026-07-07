import Combine
import CoreGraphics
import Foundation
import os

/// Consumes the typed `TapEvent` stream from `InputMonitoringCapability` and
/// interprets it against the configured activation key and mode. Hold mode is
/// inline (key-down activates, key-up deactivates); the two tap modes route each
/// completed tap through `TapStateMachine`.
@MainActor
final class HotkeyManager {
    private let inputMonitoring: InputMonitoringCapability
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "hotkey")

    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?
    /// The cancel gesture fired (planning 0017). `FreeFlowSession` guards it to
    /// `.recording`, so firing outside a recording is a harmless no-op.
    var onCancel: (() -> Void)?

    private var watchedKeyCode: Int
    private var mode: ActivationMode
    private let cancelKeyCode: Int
    private let tapMachine: TapStateMachine
    private var isKeyDown = false
    // Press latch for the cancel modifier, tracked separately from the activation
    // key so a cancel-key edge never disturbs the activation latch (and vice versa).
    private var isCancelKeyDown = false
    private var cancellables = Set<AnyCancellable>()

    init(
        inputMonitoring: InputMonitoringCapability,
        initialKeyCode: Int = Constants.defaultActivationKeyCode,
        initialMode: ActivationMode = Constants.defaultActivationMode,
        cancelKeyCode: Int = Constants.cancelKeyCode
    ) {
        self.inputMonitoring = inputMonitoring
        self.watchedKeyCode = initialKeyCode
        self.mode = initialMode
        self.cancelKeyCode = cancelKeyCode
        self.tapMachine = TapStateMachine(mode: initialMode, windowMs: Constants.doubleTapWindowMs)
    }

    func start() async {
        bindEventStream()
        await inputMonitoring.startTap()
    }

    func stop() async {
        cancellables.removeAll()
        await inputMonitoring.stopTap()
        isKeyDown = false
        isCancelKeyDown = false
    }

    /// Live-apply for the watched key. Resets the press latch so a half-press
    /// of the old key can't fire a phantom deactivate against the new one. Does
    /// NOT touch the tap machine: switching the key is a keycode refilter, and an
    /// active `.recording` must survive so the new key can stop it (a stale
    /// double-tap `awaiting` state self-clears via the time window).
    func setActivationKeyCode(_ code: Int) {
        guard watchedKeyCode != code else { return }
        logger.info("Activation key changed: \(self.watchedKeyCode, privacy: .public) -> \(code, privacy: .public)")
        watchedKeyCode = code
        isKeyDown = false
    }

    /// Live-apply for the activation mode. Resets the press latch and hands the
    /// new mode to the tap machine (which preserves an in-flight `.recording`).
    func setActivationMode(_ newMode: ActivationMode) {
        guard mode != newMode else { return }
        logger.info("Activation mode changed: \(self.mode.rawValue, privacy: .public) -> \(newMode.rawValue, privacy: .public)")
        mode = newMode
        isKeyDown = false
        tapMachine.setMode(newMode)
    }

    // internal for testability — subscribes to the capability's event stream
    // without creating a real tap, so tests can drive synthetic events through.
    func bindEventStream() {
        guard cancellables.isEmpty else { return }
        inputMonitoring.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }

    // internal for testability — pure interpretation. `.flagsChanged` for the
    // watched keycode toggles the press latch; left/right variants are
    // disambiguated by keycode, not flag bit (see activation-key-and-mode.md).
    // Hold mode fires on each edge; tap modes act only on the completing (key-up)
    // edge of a tap and delegate start/stop to the tap machine — so holding the
    // key in a tap mode is just one tap.
    func handle(_ event: TapEvent) {
        switch event {
        case .flagsChanged(let keyCode, _):
            // The cancel modifier (planning 0017) is interpreted off the same
            // already-watched `.flagsChanged` stream — no second tap, no mask change,
            // so the 0006 least-privilege posture is untouched. It's disabled when it
            // would collide with the activation key (that key already means stop);
            // the menu item remains the fallback.
            if Int(keyCode) == cancelKeyCode, cancelKeyCode != watchedKeyCode {
                handleCancelKey()
                return
            }
            guard Int(keyCode) == watchedKeyCode else { return }
            isKeyDown.toggle()
            switch mode {
            case .hold:
                if isKeyDown { fireActivate() } else { fireDeactivate() }
            case .singleTap, .doubleTap:
                guard !isKeyDown else { return }
                switch tapMachine.handleTap() {
                case .start: fireActivate()
                case .stop: fireDeactivate()
                case .none: break
                }
            }
        case .tapDisabled:
            // Capability self-heals; nothing for the manager to do.
            break
        }
    }

    // internal for testability — the cancel modifier toggles its own latch and
    // fires on the press (key-down) edge only, so one tap of the cancel key is one
    // cancel. Mode-agnostic: cancel works identically in Hold and both tap modes.
    private func handleCancelKey() {
        isCancelKeyDown.toggle()
        guard isCancelKeyDown else { return }
        logger.info("Cancel gesture (keycode \(self.cancelKeyCode, privacy: .public))")
        onCancel?()
    }

    private func fireActivate() {
        logger.info("Activate (keycode \(self.watchedKeyCode, privacy: .public), mode \(self.mode.rawValue, privacy: .public))")
        onActivate?()
    }

    private func fireDeactivate() {
        logger.info("Deactivate (keycode \(self.watchedKeyCode, privacy: .public), mode \(self.mode.rawValue, privacy: .public))")
        onDeactivate?()
    }
}
