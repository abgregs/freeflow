import Foundation

enum Constants {
    static let bundleIdentifier = "com.river.app"
    static let loggingSubsystem = "com.river.app"

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
}
