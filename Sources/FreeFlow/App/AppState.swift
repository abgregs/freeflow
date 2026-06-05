import Combine
import Foundation
import Observation

/// Observable bridge from the `AppDelegate`-owned `FreeFlowSession` (Combine
/// publishers) to SwiftUI. The menu bar — and, later, the recording-indicator
/// HUD (planning 0002) — observe this; the session itself stays UI-agnostic.
@MainActor
@Observable
final class AppState {
    private(set) var state: FreeFlowState = .idle
    private(set) var errorMessage: String?

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    func bind(to session: FreeFlowSession) {
        session.state
            .sink { [weak self] newState in self?.apply(newState) }
            .store(in: &cancellables)
        session.errors
            .sink { [weak self] error in self?.apply(error) }
            .store(in: &cancellables)
    }

    // internal for testability — the state-update entry point (also used by
    // `bind`). A fresh recording clears a stale error so the menu doesn't show
    // last cycle's failure over a new one.
    func apply(_ newState: FreeFlowState) {
        state = newState
        if newState == .recording { errorMessage = nil }
    }

    // internal for testability — the error-update entry point (also used by
    // `bind`). The single choke point where a cycle error becomes display text,
    // so `/Users/<name>` paths are redacted exactly once before reaching a
    // screen (ADR 0002).
    func apply(_ error: FreeFlowError) {
        errorMessage = LogRedaction.redactUserPaths(error.localizedDescription)
    }
}
