import Foundation

enum Constants {
    static let bundleIdentifier = "com.freeflow.app"
    static let loggingSubsystem = "com.freeflow.app"

    // Subfolder under ~/Library/Application Support holding the downloaded
    // WhisperKit model. Application Support (not WhisperKit's ~/Documents
    // default) keeps model downloads from tripping the Documents-folder TCC
    // prompt. See planning/0010_relocate-model-cache.md.
    static let modelCacheFolderName = "FreeFlow"

    // Right Option — universal on all Mac keyboards (including MacBook and
    // Magic Keyboard) and rarely pressed during typing, so Hold mode doesn't
    // accidentally trigger on capitalization or shortcuts. `@AppStorage` does
    // not bind `CGKeyCode` (a `UInt32` typealias), so the canonical type is
    // `Int`; cast at use sites.
    static let defaultActivationKeyCode: Int = 61

    // Default activation mode. Hold is the safe default — it fires on a held key
    // and works on every supported key (the tap modes add ~50–100 ms latency and
    // are the only ones reliable on Caps Lock). See requirements/activation-key-and-mode.md.
    static let defaultActivationMode: ActivationMode = .hold

    // Double-tap detection window. Two complete taps within this many milliseconds
    // start a recording. Deliberately an internal tunable, NOT a user setting:
    // exposing a slider is friction for a value the user shouldn't have to reason
    // about. 400 ms matches the platform's double-click feel.
    static let doubleTapWindowMs: Int = 400

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

    // Max UTF-16 code units per synthesized keystroke event. Text insertion
    // injects the transcription as Unicode key events (`keyboardSetUnicodeString`),
    // chunked because that call is unreliable past ~20 units in some apps. Internal
    // tunable, validated on-device. See planning/0011_keystroke-injection.md.
    static let keystrokeChunkUnits: Int = 20

    // Silence-trim energy gate: a 16 kHz window whose RMS is below this (linear
    // amplitude, not dBFS) is treated as silence and dropped from the ends of the
    // recording. Internal tunable, not a setting — the user shouldn't reason about
    // dBFS (load-bearing rule #5). Tuned against the 0022 silence corpus on-device.
    static let silenceTrimEnergyThreshold: Float = 0.01

    // Safety margin kept on each side of detected speech so onset/offset consonants
    // are never clipped by the trim. 100 ms at 16 kHz. See planning/0023.
    static let silenceTrimMarginSeconds: Double = 0.1

    // Decoding thresholds pinned to upstream Whisper defaults (planning 0023): they
    // gate silent/near-silent audio to empty output instead of hallucinated text and
    // drive the temperature fallback for low-confidence segments. WhisperKit 0.18
    // already defaults to these, but we set them explicitly so the gate can't silently
    // regress if an upstream default changes. Internal tunables, not settings.
    static let noSpeechThreshold: Float = 0.6
    static let logProbThreshold: Float = -1.0
    static let compressionRatioThreshold: Float = 2.4
    // Temperature 0 with 5 fallback increments of 0.2 reaches 1.0 — the upstream
    // Whisper schedule (temperatures 0, 0.2, 0.4, 0.6, 0.8, 1.0).
    static let decodingTemperature: Float = 0.0
    static let decodingTemperatureIncrementOnFallback: Float = 0.2
    static let decodingTemperatureFallbackCount: Int = 5
}
