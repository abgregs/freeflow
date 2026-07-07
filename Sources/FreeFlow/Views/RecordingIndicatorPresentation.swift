import Foundation

/// Pure mapping from cycle state to the recording-indicator HUD's variant and
/// on-screen visibility, extracted so the panel layer stays thin and dumb and the
/// only decidable logic (which visual to show, whether the window is on screen) is
/// unit-tested without standing up an `NSPanel` (planning 0002). Mirrors
/// `MenuBarPresentation`: the HUD is another observer of the same state seam.
enum RecordingIndicatorPresentation {
    // Mode-agnostic by construction: the variant is a function of `FreeFlowState`
    // only, so Hold / Single Tap / Double Tap produce an identical indication
    // (planning 0002 acceptance criterion 1).
    enum Variant: Equatable {
        case recording
        case processing
        case idle
    }

    static func variant(for state: FreeFlowState) -> Variant {
        switch state {
        case .idle: return .idle
        case .recording: return .recording
        case .processing: return .processing
        }
    }

    // Whether the HUD panel should be on screen right now. `.recording` /
    // `.processing` are visible; a pending error toast keeps it visible even at
    // `.idle` — errors surface at end-of-cycle, when the state has already returned
    // to `.idle`, so the toast (planning 0018) must outlive the recording that
    // triggered it. Pure so the coordinator's show-vs-fade-out branch is tested
    // without a real panel (the fade timing and focus behavior stay a documented
    // manual check — planning 0002 AC5).
    static func isOnScreen(state: FreeFlowState, hasToast: Bool) -> Bool {
        state != .idle || hasToast
    }
}
