import Combine
import CoreGraphics
import Foundation
import os

/// Consumes the typed `TapEvent` stream from `InputMonitoringCapability` and
/// interprets it against the configured activation key. M4 implements Hold mode
/// only — tap modes (`Single Tap` / `Double Tap`) land in M9 via `TapStateMachine`.
@MainActor
final class HotkeyManager {
    private let inputMonitoring: InputMonitoringCapability
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "hotkey")

    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?

    private var watchedKeyCode: Int
    private var isKeyDown = false
    private var cancellables = Set<AnyCancellable>()

    init(
        inputMonitoring: InputMonitoringCapability,
        initialKeyCode: Int = Constants.defaultActivationKeyCode
    ) {
        self.inputMonitoring = inputMonitoring
        self.watchedKeyCode = initialKeyCode
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
    /// of the old key can't fire a phantom deactivate against the new one.
    func setActivationKeyCode(_ code: Int) {
        guard watchedKeyCode != code else { return }
        logger.info("Activation key changed: \(self.watchedKeyCode, privacy: .public) -> \(code, privacy: .public)")
        watchedKeyCode = code
        isKeyDown = false
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
    // The flag value is unused in Hold mode but kept in the event shape for M9.
    func handle(_ event: TapEvent) {
        switch event {
        case .flagsChanged(let keyCode, _):
            guard Int(keyCode) == watchedKeyCode else { return }
            isKeyDown.toggle()
            if isKeyDown {
                logger.info("Activate (keycode \(self.watchedKeyCode, privacy: .public))")
                onActivate?()
            } else {
                logger.info("Deactivate (keycode \(self.watchedKeyCode, privacy: .public))")
                onDeactivate?()
            }
        case .tapDisabled:
            // Capability self-heals; nothing for the manager to do.
            break
        }
    }
}
