import Combine
import Foundation
import Observation

/// Schedules the error toast's auto-dismiss. Injected so tests fire it synchronously
/// instead of waiting on wall-clock time (planning 0018 AC4; the injectable-clock
/// pattern of `TapStateMachine`). Returns a token whose cancellation stops a pending
/// dismiss — reassigning it (a newer error) cancels the previous timer.
typealias ToastScheduler = @MainActor (_ after: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable

/// Observable bridge from the `AppDelegate`-owned `FreeFlowSession` (Combine
/// publishers) to SwiftUI. The menu bar — and the recording-indicator HUD
/// (planning 0002/0018/0020) — observe this; the session itself stays UI-agnostic.
@MainActor
@Observable
final class AppState {
    private(set) var state: FreeFlowState = .idle
    private(set) var errorMessage: String?
    private(set) var notice: String?
    /// Model load lifecycle — `.loading` until the model is warm, then `.ready`.
    /// Menu bar reads this to show "Downloading model…" / "Loading…" during launch.
    private(set) var modelLoadState: ModelLoadState = .loading
    /// Transient HUD toast (planning 0018). Distinct from `errorMessage` (the
    /// lingering menu row): it auto-dismisses after `errorToastDurationSeconds` and
    /// clears on a fresh recording. The menu row is the record; the toast is the alert.
    private(set) var toast: ErrorToast?
    /// Live input level (0...1) during recording (planning 0020). Zero at rest and
    /// whenever not recording, so the HUD meter sits still outside a capture.
    private(set) var inputLevel: Float = 0
    /// Whether the session has retained a transcript for recovery (planning 0019).
    /// Availability only — content stays in the session, never in the UI layer.
    private(set) var hasLastTranscript: Bool = false

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let scheduleToastDismiss: ToastScheduler
    @ObservationIgnored private var toastDismissal: AnyCancellable?

    // `nil` default (resolved to `liveToastScheduler` in this isolated init body)
    // rather than a default-argument reference to the main-actor static, which
    // Swift 6 forbids from the nonisolated context where defaults are evaluated.
    init(scheduleToastDismiss: ToastScheduler? = nil) {
        self.scheduleToastDismiss = scheduleToastDismiss ?? AppState.liveToastScheduler
    }

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
        session.lastTranscriptAvailable
            .sink { [weak self] available in self?.apply(hasLastTranscript: available) }
            .store(in: &cancellables)
    }

    // internal for testability — wires the model load state publisher so the
    // menu bar observes downloading/loading/ready without coupling to the manager.
    func bind(transcription: TranscriptionManager) {
        transcription.modelLoadState
            .sink { [weak self] loadState in self?.apply(modelLoadState: loadState) }
            .store(in: &cancellables)
    }

    // internal for testability — wires the mic's throttled level publisher so the
    // HUD meter observes input level without the level path crossing through the
    // session (mirrors `bind(transcription:)`; planning 0020). The mic is the one
    // `AVAudioEngine` owner and computes the level; this only forwards it.
    func bind(microphone: MicrophoneCapability) {
        microphone.inputLevels
            .sink { [weak self] level in self?.apply(inputLevel: level) }
            .store(in: &cancellables)
    }

    // internal for testability — the state-update entry point (also used by
    // `bind`). A fresh recording clears a stale error so the menu doesn't show
    // last cycle's failure over a new one. A recording-context notice is tied to
    // the live recording, so it clears the moment that recording ends.
    func apply(_ newState: FreeFlowState) {
        state = newState
        if newState == .recording {
            errorMessage = nil
            // A fresh recording clears a stale toast too (its lingering-record twin
            // stays on the menu row); its own auto-dismiss timer is now moot.
            toast = nil
            toastDismissal = nil
        }
        if newState != .recording {
            notice = nil
            // The meter sits at rest outside a live recording; a late buffer must
            // not leave the last level frozen on screen after the cycle ends.
            inputLevel = 0
        }
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
        // Graduate the same error into a transient HUD toast (planning 0018). The
        // toast is fixed copy per error *kind* — no user content — so it needs no
        // redaction; the redacted framework message stays on `errorMessage` only.
        // Reassigning `toastDismissal` cancels any previous pending dismiss, so the
        // newest error owns the timer.
        toast = ErrorToastPresentation.toast(for: error)
        toastDismissal = scheduleToastDismiss(Constants.errorToastDurationSeconds) { [weak self] in
            self?.dismissToast()
        }
    }

    // internal for testability — the model load state entry point (also used by
    // `bind(transcription:)`). Drives the menu bar's download/load/ready label.
    func apply(modelLoadState: ModelLoadState) {
        self.modelLoadState = modelLoadState
    }

    // internal for testability — the level entry point (also used by
    // `bind(microphone:)`). Ignored outside `.recording` so a late buffer can't
    // raise the meter after the cycle has returned to idle/processing.
    func apply(inputLevel level: Float) {
        guard state == .recording else { return }
        inputLevel = level
    }

    // internal for testability — drives `hasLastTranscript` from the session's
    // `lastTranscriptAvailable` publisher (planning 0019). Availability only —
    // the content stays in the session.
    func apply(hasLastTranscript available: Bool) {
        hasLastTranscript = available
    }

    // internal for testability — clears the toast when its timer fires. Separate so
    // the scheduled closure has a named target and the fired-clear is observable.
    func dismissToast() {
        toast = nil
        toastDismissal = nil
    }

    // Production toast scheduler: a cancelable main-queue delay. Cancelling the
    // returned token (via reassignment or `dismissToast`) stops a pending fire.
    static let liveToastScheduler: ToastScheduler = { seconds, action in
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return AnyCancellable { work.cancel() }
    }
}
