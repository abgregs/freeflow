import AppKit
import Foundation

/// Which audible cue to play. Begin fires on `.idle → .recording`;
/// end fires on `.recording → .processing`.
enum SoundCue: Equatable {
    case begin
    case end
}

/// Plays a `SoundCue`. Injected so tests replace the real OS call with a recording fake.
protocol SoundFeedbackPlaying: AnyObject {
    func play(_ cue: SoundCue)
}

/// Live player: one-shot `NSSound` per cue using named system sounds — no bundle
/// assets needed (planning 0016 design). `NSSound(named:)` returns nil if the
/// sound file is missing; treated as a graceful no-op since the cue is cosmetic.
final class NSSoundPlayer: SoundFeedbackPlaying {
    func play(_ cue: SoundCue) {
        let name: NSSound.Name
        switch cue {
        case .begin: name = NSSound.Name("Tink")
        case .end:   name = NSSound.Name("Funk")
        }
        NSSound(named: name)?.play()
    }
}

/// Observes the `AppState` state seam and plays audible recording cues behind the
/// `Settings.playFeedbackSounds` toggle (planning 0016). A sibling of
/// `RecordingIndicatorCoordinator` — another pure observer of the same seam.
/// Mode-agnostic by construction: it observes state transitions, not the activation
/// path, so Hold / Single Tap / Double Tap produce identical cues.
@MainActor
final class SoundFeedbackController {
    private let appState: AppState
    private let settings: SettingsStore
    private let player: any SoundFeedbackPlaying
    // Previous state tracked so the transition, not just the current state, determines which cue.
    private var previousState: FreeFlowState = .idle

    init(appState: AppState, settings: SettingsStore, player: (any SoundFeedbackPlaying)? = nil) {
        self.appState = appState
        self.settings = settings
        self.player = player ?? NSSoundPlayer()
    }

    func start() {
        previousState = appState.state
        observeAppState()
    }

    // Re-arm observation on each change (Observation's `onChange` is one-shot),
    // mirroring the `RecordingIndicatorCoordinator` pattern.
    private func observeAppState() {
        withObservationTracking {
            _ = appState.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.handleStateChange()
                self.observeAppState()
            }
        }
    }

    // internal for testability — the cue-decision entry point. The observation
    // loop calls this on each state change; tests call it directly after adjusting
    // `appState.state` via `apply(_:)`, bypassing the async observation loop.
    func handleStateChange() {
        let newState = appState.state
        defer { previousState = newState }
        guard let cue = SoundFeedbackController.cue(from: previousState, to: newState) else { return }
        guard settings.value(for: Settings.playFeedbackSounds) else { return }
        player.play(cue)
    }

    // internal for testability — pure transition → cue mapping. Returns nil for
    // transitions that carry no sound (e.g. `.processing → .idle`).
    static func cue(from: FreeFlowState, to: FreeFlowState) -> SoundCue? {
        switch (from, to) {
        case (.idle, .recording):       return .begin
        case (.recording, .processing): return .end
        default:                        return nil
        }
    }
}
