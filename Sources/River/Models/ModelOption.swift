import Foundation

/// One entry in the curated WhisperKit model picker: the exact repo name
/// WhisperKit downloads from `argmaxinc/whisperkit-coreml`, a human label, and a
/// one-line size/speed/accuracy hint for the Settings UI. Pure presentation data,
/// unit-tested without SwiftUI (mirrors `ActivationKeyOption`). The curated list
/// itself lives in `Constants.curatedModels`.
struct ModelOption: Identifiable, Equatable {
    /// WhisperKit repo folder name, e.g. `openai_whisper-small.en`. Passed
    /// verbatim to `WhisperKit(model:)` and used as the on-disk cache directory.
    let name: String
    let label: String
    let hint: String
    var id: String { name }
}
