import Testing
@testable import FreeFlow

@Suite("LevelMeterPresentation")
struct LevelMeterPresentationTests {
    // The level → lit-bar-count mapping is a pure function (planning 0020 AC4). It
    // must anchor the endpoints (silence lights none, full lights all) and clamp
    // out-of-range input so a stray above-reference sample can't overflow the bars.

    @Test("silence lights no bars; full level lights all")
    func endpoints() {
        #expect(LevelMeterPresentation.litBars(level: 0, barCount: 12) == 0)
        #expect(LevelMeterPresentation.litBars(level: 1, barCount: 12) == 12)
    }

    @Test("a mid level lights proportionally")
    func proportional() {
        #expect(LevelMeterPresentation.litBars(level: 0.5, barCount: 8) == 4)
        #expect(LevelMeterPresentation.litBars(level: 0.25, barCount: 8) == 2)
    }

    @Test("out-of-range input is clamped, never overflowing the bar array")
    func clamped() {
        // A transient above the reference RMS normalizes >1 before clamping; if this
        // returned >barCount the view would index past its bar array.
        #expect(LevelMeterPresentation.litBars(level: 1.8, barCount: 12) == 12)
        #expect(LevelMeterPresentation.litBars(level: -0.5, barCount: 12) == 0)
    }

    @Test("a zero bar count lights nothing")
    func zeroBarCount() {
        #expect(LevelMeterPresentation.litBars(level: 1, barCount: 0) == 0)
    }
}
