import Testing
@testable import FreeFlow

@Suite("ActivationMode")
struct ActivationModeTests {
    @Test("table lists all three modes with the default and non-empty copy")
    func tableComplete() {
        #expect(ActivationMode.allCases.count == 3)
        #expect(Settings.activationMode.defaultValue == .hold)
        for mode in ActivationMode.allCases {
            #expect(!mode.label.isEmpty)
            #expect(!mode.description.isEmpty)
        }
    }

    @Test("notice copy names the changed key and mode")
    func noticeCopy() {
        // If the copy stops naming the new key/mode, the user can't tell what now
        // stops the recording — the whole point of the live-apply notice.
        #expect(ActivationNotice.keyChanged(toKeyCode: 61).contains("Right Option"))
        #expect(ActivationNotice.modeChanged(to: .doubleTap).contains("Double Tap"))
    }

    @Test("keyChanged falls back to generic phrasing for an unknown keycode")
    func keyChangedUnknownKeycode() {
        // A keycode absent from `ActivationKeyOption.all` (e.g. a future/removed
        // key) must not crash or emit a blank label — the `?? "the new key"`
        // fallback keeps the notice grammatical.
        let notice = ActivationNotice.keyChanged(toKeyCode: -1)
        #expect(notice.contains("the new key"))
    }
}
