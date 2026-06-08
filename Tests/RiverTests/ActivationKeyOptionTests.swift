import Testing
@testable import River

@Suite("ActivationKeyOption")
struct ActivationKeyOptionTests {
    @Test("table lists all 10 supported keys, no duplicate keycodes, includes the default")
    func tableComplete() {
        #expect(ActivationKeyOption.all.count == 10)
        let codes = Set(ActivationKeyOption.all.map(\.keyCode))
        #expect(codes.count == 10)
        #expect(codes.contains(Settings.activationKeyCode.defaultValue))  // 61, Right Option
    }

    @Test("Caps Lock + Hold warns; other keys do not")
    func capsLockWarning() {
        // Why: Hold mode is broken on Caps Lock (it toggles on press, not held).
        // The inline warning is the inform-don't-block surface; if it stops firing
        // the user gets a silently broken hotkey (supported-keys-and-limitations.md).
        let warning = ActivationKeyOption.capsLockHoldWarning(keyCode: ActivationKeyOption.capsLockKeyCode)
        #expect(warning != nil)
        #expect(warning?.contains("Hold mode") == true)
        #expect(ActivationKeyOption.capsLockHoldWarning(keyCode: 61) == nil)  // Right Option
    }
}
