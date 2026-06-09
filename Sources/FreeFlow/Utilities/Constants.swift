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

    // WhisperKit model identifier. `small.en` is the default because the custom
    // dictionary (prompt-token biasing) is unreliable on smaller models: `base.en`
    // degenerates to empty output when given a prompt (verified via the A/B eval
    // harness — see requirements/custom-dictionary.md). `small.en` (~240 MB) handles
    // prompts robustly and is more accurate, at some cost in speed/memory. A model
    // picker (deferred, M9+) can let speed-focused users drop back to `base.en`.
    static let defaultModel: String = "openai_whisper-small.en"

    // Seed for the user-editable custom dictionary. Empty by default; the user
    // curates terms in Settings (M8). A curated starter list could be added here
    // later. See requirements/custom-dictionary.md.
    static let defaultDictionaryTerms: [String] = []

    // Gap between writing the transcription to the pasteboard + posting ⌘V and
    // restoring the user's original clipboard. 250 ms is the empirically smallest
    // delay that lets the target app's paste handler actually pull the new
    // contents in before they're overwritten — going lower lets the restore race
    // the paste and the user sees their own clipboard re-pasted. See M7 in
    // architecture/free-flow-pipeline.md step 6.
    static let clipboardRestoreDelay: TimeInterval = 0.25
}
