import Testing
@testable import FreeFlow

@Suite("RecordingIndicatorPresentation")
struct RecordingIndicatorPresentationTests {
    // The HUD's state→variant mapping is the recording-indicator analogue of
    // MenuBarPresentation. Pinning it means a symbol/behavior change is a
    // deliberate edit with a failing test, not silent drift (planning 0002 AC5).

    @Test("variant reflects each cycle state, mode-agnostically")
    func variantPerState() {
        // Mode-agnostic by construction: the variant is a function of state only,
        // so Hold / Single Tap / Double Tap all produce the same indication
        // (planning 0002 AC1). There is no mode input to get wrong.
        #expect(RecordingIndicatorPresentation.variant(for: .idle) == .idle)
        #expect(RecordingIndicatorPresentation.variant(for: .recording) == .recording)
        #expect(RecordingIndicatorPresentation.variant(for: .processing) == .processing)
    }

    @Test("recording and processing are on screen; idle without a toast is not")
    func visibilityPerState() {
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .recording, hasToast: false))
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .processing, hasToast: false))
        #expect(!RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: false))
    }

    @Test("a pending toast keeps the panel on screen at idle")
    func toastKeepsPanelVisibleAtIdle() {
        // Errors surface at end-of-cycle, when the state has already returned to
        // .idle. If the panel dropped the moment state hit .idle, the toast would
        // never be seen. The toast must outlive the recording that triggered it.
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: true))
    }
}
