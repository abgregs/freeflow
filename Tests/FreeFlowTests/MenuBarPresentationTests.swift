import Testing
@testable import FreeFlow

@Suite("MenuBarPresentation")
struct MenuBarPresentationTests {
    // The icon/label contract is the user-visible half of requirement
    // core-feature.md item 5. These pin it so a symbol or copy change is a
    // deliberate edit with a failing test, not a silent drift.
    @Test("icon and label reflect each cycle state when model is ready")
    func visualPerState() {
        #expect(MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .ready)
            == .init(systemImage: "mic", statusLabel: "Ready"))
        #expect(MenuBarPresentation.visual(state: .recording, hasError: false, modelLoadState: .ready)
            == .init(systemImage: "mic.fill", statusLabel: "Recording..."))
        #expect(MenuBarPresentation.visual(state: .processing, hasError: false, modelLoadState: .ready)
            == .init(systemImage: "ellipsis", statusLabel: "Processing..."))
    }

    @Test("a pending error overrides the idle icon but keeps the status label")
    func errorOverridesIdleIcon() {
        let visual = MenuBarPresentation.visual(state: .idle, hasError: true, modelLoadState: .ready)
        #expect(visual.systemImage == "exclamationmark.triangle")
        #expect(visual.statusLabel == "Ready")
    }

    @Test("an active state's icon wins over a pending error")
    func activeStateIconWinsOverError() {
        // Errors surface at end-of-cycle; a recording/processing icon must not
        // be masked by a stale error from the previous cycle.
        #expect(MenuBarPresentation.visual(state: .recording, hasError: true, modelLoadState: .ready).systemImage == "mic.fill")
        #expect(MenuBarPresentation.visual(state: .processing, hasError: true, modelLoadState: .ready).systemImage == "ellipsis")
    }

    // MARK: - Load state mapping (planning 0004 AC4)

    @Test("downloading state shows download icon and 'Downloading model...' label")
    func downloadingState() {
        // Cold launch: model files not yet on disk. The menu must show progress,
        // not "Ready" — "Ready" while the model is still downloading is a lie.
        let visual = MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .downloading)
        #expect(visual.systemImage == "arrow.down.circle")
        #expect(visual.statusLabel == "Downloading model...")
    }

    @Test("loading state shows ellipsis icon and 'Loading...' label")
    func loadingState() {
        // Warm launch: files on disk, CoreML loading into memory. Still not "Ready".
        let visual = MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .loading)
        #expect(visual.systemImage == "ellipsis")
        #expect(visual.statusLabel == "Loading...")
    }

    @Test("failed state shows error icon and an honest failure label")
    func failedState() {
        // "Ready" after a failed load would be the exact menu-bar lie 0004 removes:
        // dictation cannot work until relaunch, so the label must say so.
        let visual = MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .failed)
        #expect(visual.systemImage == "exclamationmark.triangle")
        #expect(visual.statusLabel == "Model failed to load")
    }

    @Test("load state does not affect recording or processing icons")
    func loadStateDoesNotAffectActiveStates() {
        // Active states are visible feedback during a live recording/paste cycle.
        // They must never be masked by the model load state (which is satisfied
        // before recording is permitted — the session gates on .ready).
        #expect(MenuBarPresentation.visual(state: .recording, hasError: false, modelLoadState: .loading).systemImage == "mic.fill")
        #expect(MenuBarPresentation.visual(state: .processing, hasError: false, modelLoadState: .loading).systemImage == "ellipsis")
        #expect(MenuBarPresentation.visual(state: .recording, hasError: false, modelLoadState: .downloading).systemImage == "mic.fill")
    }

    @Test("default modelLoadState is .ready (backward-compatible call sites)")
    func defaultModelLoadStateIsReady() {
        // `visual(state:hasError:)` callers that don't pass modelLoadState must
        // continue to work correctly after adding the parameter.
        #expect(MenuBarPresentation.visual(state: .idle, hasError: false)
            == .init(systemImage: "mic", statusLabel: "Ready"))
    }
}
