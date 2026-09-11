import Foundation

/// Pure mapping from cycle state to the menu-bar icon + status label, extracted
/// so the icon/label contract is unit-tested without standing up SwiftUI.
enum MenuBarPresentation {
    struct Visual: Equatable {
        let systemImage: String
        let statusLabel: String
    }

    // core-feature.md item 5: empty mic (.idle) / filled mic (.recording) /
    // three-dot (.processing); labels "Ready" / "Recording..." / "Processing...".
    // A pending error overrides the *idle* icon with a warning glyph — errors
    // surface at end-of-cycle, so an active state's icon always wins.
    //
    // During the model load window (planning 0004), the idle state shows the load
    // progress ("Downloading model…" / "Loading…") instead of "Ready". Active cycle
    // states (.recording / .processing) are never masked — the model is ready before
    // recording is permitted, so the load state only affects the idle presentation.
    static func visual(state: FreeFlowState, hasError: Bool, modelLoadState: ModelLoadState = .ready) -> Visual {
        // Non-idle states are unaffected by model load state.
        guard state == .idle else {
            let systemImage: String
            switch state {
            case .idle: systemImage = "mic"  // unreachable (guard above), kept for exhaustiveness
            case .recording: systemImage = "mic.fill"
            case .processing: systemImage = "ellipsis"
            }
            let statusLabel: String
            switch state {
            case .idle: statusLabel = "Ready"
            case .recording: statusLabel = "Recording..."
            case .processing: statusLabel = "Processing..."
            }
            return Visual(systemImage: systemImage, statusLabel: statusLabel)
        }

        // Idle + model still loading: show download/load progress instead of "Ready".
        switch modelLoadState {
        case .downloading:
            return Visual(systemImage: "arrow.down.circle", statusLabel: "Downloading model...")
        case .loading:
            return Visual(systemImage: "ellipsis", statusLabel: "Loading...")
        case .failed:
            // "Ready" here would be the exact lie 0004 removes — dictation cannot
            // work until relaunch, so the label says so alongside the glyph. (The
            // session also emits a .transcription error if the user tries anyway.)
            return Visual(systemImage: "exclamationmark.triangle", statusLabel: "Model failed to load")
        case .ready:
            let icon = hasError ? "exclamationmark.triangle" : "mic"
            return Visual(systemImage: icon, statusLabel: "Ready")
        }
    }
}
