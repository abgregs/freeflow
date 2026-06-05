import Foundation

enum Constants {
    static let bundleIdentifier = "com.freeflow.app"
    static let loggingSubsystem = "com.freeflow.app"

    // Right Option — universal on all Mac keyboards (including MacBook and
    // Magic Keyboard) and rarely pressed during typing, so Hold mode doesn't
    // accidentally trigger on capitalization or shortcuts. `@AppStorage` does
    // not bind `CGKeyCode` (a `UInt32` typealias), so the canonical type is
    // `Int`; cast at use sites.
    static let defaultActivationKeyCode: Int = 61

    // WhisperKit model identifier. `base.en` is the smallest English-only
    // model that gives reasonable accuracy for dictation while staying ~140 MB
    // on disk. The user-tunable picker lands in M8; see configuration.md.
    static let defaultModel: String = "openai_whisper-base.en"

    // Gap between writing the transcription to the pasteboard + posting ⌘V and
    // restoring the user's original clipboard. 250 ms is the empirically smallest
    // delay that lets the target app's paste handler actually pull the new
    // contents in before they're overwritten — going lower lets the restore race
    // the paste and the user sees their own clipboard re-pasted. See M7 in
    // architecture/free-flow-pipeline.md step 6.
    static let clipboardRestoreDelay: TimeInterval = 0.25
}
