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
    static func visual(state: FreeFlowState, hasError: Bool) -> Visual {
        let systemImage: String
        if hasError, state == .idle {
            systemImage = "exclamationmark.triangle"
        } else {
            switch state {
            case .idle: systemImage = "mic"
            case .recording: systemImage = "mic.fill"
            case .processing: systemImage = "ellipsis"
            }
        }
        let statusLabel: String
        switch state {
        case .idle: statusLabel = "Ready"
        case .recording: statusLabel = "Recording..."
        case .processing: statusLabel = "Processing..."
        }
        return Visual(systemImage: systemImage, statusLabel: statusLabel)
    }
}
