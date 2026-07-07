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

    // Cancel gesture (planning 0017). Tapping this modifier key while recording
    // discards the in-flight recording — no transcription, no paste. It MUST be a
    // *modifier* keycode, because the event tap observes `.flagsChanged` only and
    // never `keyDown` (the 0006 least-privilege posture — see
    // planning/0006_runtime-security-hardening.md); Escape (a keyDown) is therefore
    // off-limits without widening the tap. fn/Globe (63) is universal on Apple
    // keyboards, is rarely chorded during dictation (unlike Command/Control/Shift,
    // which would false-cancel on every shortcut), and is distinct from the default
    // activation key. The menu-bar "Cancel Recording" item is the always-available
    // discoverable fallback. Internal tunable, not a user setting (load-bearing rule
    // #5). If it ever equals the watched activation key the gesture disables itself
    // (the menu item still works). Verify fn delivers a `.flagsChanged` with keycode
    // 63 on-device — the Globe key is special-cased on some keyboards.
    static let cancelKeyCode: Int = 63

    // Double-tap detection window. Two complete taps within this many milliseconds
    // start a recording. Deliberately an internal tunable, NOT a user setting:
    // exposing a slider is friction for a value the user shouldn't have to reason
    // about. 400 ms matches the platform's double-click feel.
    static let doubleTapWindowMs: Int = 400

    // WhisperKit model identifier. `small.en` is the default because the custom
    // dictionary (prompt-token biasing) is unreliable on smaller models: `base.en`
    // degenerates to empty output when given a prompt (verified via the A/B eval
    // harness — see requirements/custom-dictionary.md). `small.en` (~240 MB) handles
    // prompts robustly and is more accurate, at some cost in speed/memory. The model
    // picker (planning 0021) lets speed-focused users drop back to `base.en`; this is
    // the default the `Settings.selectedModel` key sources.
    static let defaultModel: String = "openai_whisper-small.en"

    // PROVISIONAL curated list for the model picker (planning 0021). The final list
    // and default are decided by 0022's per-model scorecards, which don't exist yet —
    // these four are placeholders: the two known-good English models plus two stronger
    // candidates that have never been evaluated here. Names are the exact
    // `argmaxinc/whisperkit-coreml` repo folders WhisperKit downloads (verified against
    // WhisperKit 0.18's model tables). Sizes are approximate on-disk footprints. Each
    // entry must earn its place via a 0022 scorecard before this list is finalized.
    static let curatedModels: [ModelOption] = [
        ModelOption(
            name: "openai_whisper-base.en",
            label: "Base (English)",
            hint: "Fastest, smallest (~150 MB). Lower accuracy."
        ),
        ModelOption(
            name: defaultModel,   // openai_whisper-small.en
            label: "Small (English)",
            hint: "Balanced speed and accuracy (~240 MB). Current default."
        ),
        ModelOption(
            name: "distil-whisper_distil-large-v3",
            label: "Distil Large v3",
            hint: "High accuracy, distilled for speed (~600 MB)."
        ),
        ModelOption(
            name: "openai_whisper-large-v3-v20240930_turbo",
            label: "Large v3 Turbo",
            hint: "Most accurate, turbo decoding (~630 MB). Slowest to load."
        ),
    ]

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

    // Recording-indicator HUD (planning 0002/0018/0020). These are internal
    // tunables, NOT settings: the HUD has no user-facing configuration (load-bearing
    // rule #5), so its timing, layout, and thresholds live here.

    // Fade in/out duration for the HUD panel. The panel is ordered out only after
    // this outlives the return to `.idle`, so the fade animation completes on screen
    // before the window is removed (planning 0002 acceptance criterion 2).
    static let hudFadeSeconds: Double = 0.22
    // Gap between the HUD panel and the bottom of the active screen's visible frame.
    static let hudBottomMargin: Double = 120

    // How long an error toast stays on the HUD before auto-dismissing (planning
    // 0018 acceptance criterion 1). Long enough to read a headline + hint, short
    // enough to "get out of the way."
    static let errorToastDurationSeconds: Double = 4.0

    // Mic level meter (planning 0020). Bars in the meter; the publish interval
    // throttles the level publisher to ~14 Hz (plenty for a meter, far below the
    // ~43 buffers/sec the tap delivers); the reference RMS is the linear amplitude
    // mapped to a full-scale meter (a ~0.2 RMS speech peak lights every bar).
    static let levelMeterBarCount: Int = 12
    static let levelMeterPublishInterval: Double = 0.07
    static let levelMeterReferenceRMS: Float = 0.2
}
