import Foundation

/// Pure mapping from a normalized input level (0...1) to the meter's visual, so
/// the "how many bars light" contract is unit-tested without standing up SwiftUI
/// (planning 0020 acceptance criterion 4). The RMS→level computation lives in
/// `MicrophoneCapability` (the one `AVAudioEngine` owner); this is only the render
/// mapping.
enum LevelMeterPresentation {
    // Number of lit bars for a level. A level of 0 lights none (silence sits at
    // rest); a level of 1 lights all. Out-of-range input is clamped so a stray
    // above-reference sample can't overflow the bar array.
    static func litBars(level: Float, barCount: Int) -> Int {
        guard barCount > 0 else { return 0 }
        let clamped = min(max(level, 0), 1)
        return Int((clamped * Float(barCount)).rounded())
    }
}
