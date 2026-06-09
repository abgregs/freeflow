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

    private var watchedKeyCode: Int
    private var mode: ActivationMode
    private let tapMachine: TapStateMachine
    private var isKeyDown = false
    private var cancellables = Set<AnyCancellable>()

    init(
        inputMonitoring: InputMonitoringCapability,
        initialKeyCode: Int = Constants.defaultActivationKeyCode,
        initialMode: ActivationMode = Constants.defaultActivationMode
    ) {
        self.inputMonitoring = inputMonitoring
        self.watchedKeyCode = initialKeyCode
        self.mode = initialMode
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

    private func fireActivate() {
        logger.info("Activate (keycode \(self.watchedKeyCode, privacy: .public), mode \(self.mode.rawValue, privacy: .public))")
        onActivate?()
    }

    private func fireDeactivate() {
        logger.info("Deactivate (keycode \(self.watchedKeyCode, privacy: .public), mode \(self.mode.rawValue, privacy: .public))")
        onDeactivate?()
    }
}
