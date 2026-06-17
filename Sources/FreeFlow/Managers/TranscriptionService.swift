import Foundation
import WhisperKit
import os

enum TranscriptionError: Error, LocalizedError {
    /// `transcribe` was called before `loadModel` completed. The session
    /// surfaces this in the log; M7 will fold it into the user-visible error
    /// surface alongside paste failures.
    case modelNotLoaded
    case transcriptionFailed(underlying: Error)
    /// WhisperKit returned no text for a non-empty audio buffer. Distinct from
    /// the no-audio path (`AudioCaptureError.noAudioCaptured` in M5) so the
    /// log shows *what* failed.
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded yet."
        case .transcriptionFailed(let underlying):
            return "Transcription failed: \(underlying.localizedDescription)"
        case .emptyTranscription:
            return "Transcription returned no text."
        }
    }
}

@MainActor
final class TranscriptionService {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "transcribe")
    private let modelName: String

    private var whisperKit: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?

    /// User-curated terms that bias decoding toward proper nouns and jargon.
    /// M8 will wire `Settings.customDictionaryTerms` → `setCustomDictionaryTerms`.
    /// Until then, the list is empty; the special-token filter still runs and
    /// no-ops correctly on the empty case (custom-dictionary.md).
    private var customDictionaryTerms: [String] = []

    init(modelName: String = Constants.defaultModel) {
        self.modelName = modelName
    }

    // internal for testability — the model download root. Application Support
    // (not WhisperKit's ~/Documents default) so model downloads never trip the
    // Documents-folder TCC prompt (planning 0010). Pure (no I/O); `loadModel`
    // creates the directory.
    static func modelDownloadBase() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Constants.modelCacheFolderName, isDirectory: true)
    }

    /// Idempotent. AppDelegate kicks this off as fire-and-forget at launch.
    /// Coalesces concurrent callers onto the same `Task` so a second `loadModel`
    /// while the first is in-flight doesn't start a second download.
    func loadModel() async throws {
        if whisperKit != nil { return }
        if let loadTask {
            _ = try await loadTask.value
            return
        }
        logger.info("Loading WhisperKit model \(self.modelName, privacy: .public)")
        let modelName = self.modelName
        let task = Task<WhisperKit, Error> {
            // Download under Application Support, not WhisperKit's default of
            // ~/Documents/huggingface — Documents is TCC-protected, so the default
            // triggers a "FreeFlow wants to access Documents" prompt and clutters
            // the user's Documents (planning 0010).
            let downloadBase = Self.modelDownloadBase()
            try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
            // `load: true` is required: without it (and without a `modelFolder`),
            // WhisperKit's init downloads but does NOT call `loadModels()`, so the
            // encoder/decoder/tokenizer stay nil until the first `transcribe`
            // lazy-loads them. That broke two things: the "model loads at launch"
            // guarantee, and the custom dictionary — `buildPromptTokens` read a nil
            // `tokenizer` and silently produced an empty prompt.
            return try await WhisperKit(model: modelName, downloadBase: downloadBase, load: true)
        }
        loadTask = task
        do {
            let wk = try await task.value
            whisperKit = wk
            logger.info("WhisperKit model loaded")
        } catch {
            loadTask = nil
            logger.error("WhisperKit load failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    func setCustomDictionaryTerms(_ terms: [String]) {
        customDictionaryTerms = terms
    }

    /// Returns the transcribed text or throws. Throws `.modelNotLoaded` if
    /// `loadModel` hasn't completed (the fail-fast surface — the session logs
    /// and still returns the cycle to `.idle`).
    func transcribe(audioSamples: [Float]) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        logger.info("Transcribing \(audioSamples.count, privacy: .public) samples")

        let promptTokens = buildPromptTokens(using: whisperKit)
        var text = try await decode(audioSamples, promptTokens: promptTokens, using: whisperKit)

        // A custom-dictionary prompt must only ever *help*. A small model like
        // `base.en` can occasionally emit empty output when conditioned on a
        // prompt; without this, adding a dictionary term could turn a working
        // dictation into a hard `.emptyTranscription` error — strictly worse than
        // no dictionary. Retry unprompted so the dictionary degrades to neutral.
        // A genuinely silent recording still errors honestly (the retry is also
        // empty). Logged so prompt-quality regressions stay observable.
        if text.isEmpty, !promptTokens.isEmpty {
            logger.warning("Prompted transcription was empty; retrying without the custom-dictionary prompt")
            text = try await decode(audioSamples, promptTokens: [], using: whisperKit)
        }

        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }
        logger.info("Transcribed \(text.count, privacy: .public) chars")
        return text
    }

    private func decode(_ audioSamples: [Float], promptTokens: [Int], using whisperKit: WhisperKit) async throws -> String {
        let options = DecodingOptions(promptTokens: promptTokens.isEmpty ? nil : promptTokens)
        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
        } catch {
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // internal for the manual A/B eval harness (`DictionaryEvalTests`) — NOT used
    // in production. Loads one fixed clip and decodes it twice: with the current
    // custom-dictionary prompt and without, **bypassing** `transcribe`'s empty
    // fallback, so the harness can see whether the prompt degenerates (empty) or
    // actually biases the output. The clip is the only thing held constant; the
    // prompt is the only variable.
    func evaluateDictionaryPrompt(wavPath: String) async throws -> (promptTokenCount: Int, off: String, on: String) {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavPath)
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        let promptTokens = buildPromptTokens(using: whisperKit)
        let off = try await decode(samples, promptTokens: [], using: whisperKit)
        let on = try await decode(samples, promptTokens: promptTokens, using: whisperKit)
        return (promptTokens.count, off, on)
    }

    private func buildPromptTokens(using whisperKit: WhisperKit) -> [Int] {
        guard !customDictionaryTerms.isEmpty, let tokenizer = whisperKit.tokenizer else { return [] }
        let prompt = " " + customDictionaryTerms.joined(separator: ", ")
        let raw = tokenizer.encode(text: prompt)
        return Self.filterSpecialTokens(raw, specialTokenBegin: tokenizer.specialTokens.specialTokenBegin)
    }

    // internal for testability — the load-bearing custom-dictionary filter.
    // Tokens at or above `specialTokenBegin` are timestamp / language / sentinel
    // tokens; injecting them into `promptTokens` silently corrupts decoding
    // (custom-dictionary.md). Pure function, exercised on synthetic inputs.
    static func filterSpecialTokens(_ tokens: [Int], specialTokenBegin: Int) -> [Int] {
        tokens.filter { $0 < specialTokenBegin }
    }
}
