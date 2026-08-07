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
    private(set) var notice: String?
    /// Model load lifecycle — `.loading` until the model is warm, then `.ready`.
    /// Menu bar reads this to show "Downloading model…" / "Loading…" during launch.
    private(set) var modelLoadState: ModelLoadState = .loading

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    func bind(to session: FreeFlowSession) {
        session.state
            .sink { [weak self] newState in self?.apply(newState) }
            .store(in: &cancellables)
        session.errors
            .sink { [weak self] error in self?.apply(error) }
            .store(in: &cancellables)
        session.notices
            .sink { [weak self] notice in self?.apply(notice: notice) }
            .store(in: &cancellables)
    }

    // internal for testability — wires the model load state publisher so the
    // menu bar observes downloading/loading/ready without coupling to the manager.
    func bind(transcription: TranscriptionManager) {
        transcription.modelLoadState
            .sink { [weak self] loadState in self?.apply(modelLoadState: loadState) }
            .store(in: &cancellables)
    }

    // internal for testability — the state-update entry point (also used by
    // `bind`). A fresh recording clears a stale error so the menu doesn't show
    // last cycle's failure over a new one. A recording-context notice is tied to
    // the live recording, so it clears the moment that recording ends.
    func apply(_ newState: FreeFlowState) {
        state = newState
        if newState == .recording { errorMessage = nil }
        if newState != .recording { notice = nil }
    }

    // internal for testability — a recording-context notice (e.g. a live
    // activation-settings change). Set during `.recording`; see `apply(_:)` for
    // the clear-on-end lifecycle.
    func apply(notice: String) {
        self.notice = notice
    }

    // internal for testability — the error-update entry point (also used by
    // `bind`). The single choke point where a cycle error becomes display text,
    // so `/Users/<name>` paths are redacted exactly once before reaching a
    // screen (ADR 0002).
    func apply(_ error: FreeFlowError) {
        errorMessage = LogRedaction.redactUserPaths(error.localizedDescription)
    }

    // internal for testability — the model load state entry point (also used by
    // `bind(transcription:)`). Drives the menu bar's download/load/ready label.
    func apply(modelLoadState: ModelLoadState) {
        self.modelLoadState = modelLoadState
    }
}
