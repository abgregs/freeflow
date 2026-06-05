import Testing
@testable import FreeFlow

@Suite("MenuBarPresentation")
struct MenuBarPresentationTests {
    // The icon/label contract is the user-visible half of requirement
    // core-feature.md item 5. These pin it so a symbol or copy change is a
    // deliberate edit with a failing test, not a silent drift.
    @Test("icon and label reflect each cycle state")
    func visualPerState() {
        #expect(MenuBarPresentation.visual(state: .idle, hasError: false)
            == .init(systemImage: "mic", statusLabel: "Ready"))
        #expect(MenuBarPresentation.visual(state: .recording, hasError: false)
            == .init(systemImage: "mic.fill", statusLabel: "Recording..."))
        #expect(MenuBarPresentation.visual(state: .processing, hasError: false)
            == .init(systemImage: "ellipsis", statusLabel: "Processing..."))
    }

    @Test("a pending error overrides the idle icon but keeps the status label")
    func errorOverridesIdleIcon() {
        let visual = MenuBarPresentation.visual(state: .idle, hasError: true)
        #expect(visual.systemImage == "exclamationmark.triangle")
        #expect(visual.statusLabel == "Ready")
    }

    @Test("an active state's icon wins over a pending error")
    func activeStateIconWinsOverError() {
        // Errors surface at end-of-cycle; a recording/processing icon must not
        // be masked by a stale error from the previous cycle.
        #expect(MenuBarPresentation.visual(state: .recording, hasError: true).systemImage == "mic.fill")
        #expect(MenuBarPresentation.visual(state: .processing, hasError: true).systemImage == "ellipsis")
    }
}
