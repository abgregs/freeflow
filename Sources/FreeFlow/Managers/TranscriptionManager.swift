import Combine
import Foundation
import WhisperKit
import os

/// Load lifecycle for the transcription model, published so the menu bar can
/// show an honest status during the download/load window on launch.
///
/// State machine:
///   (cold) downloading → loading → ready
///   (warm)              loading → ready
///   (error) any        →          failed
enum ModelLoadState: Equatable {
    /// Model files are being fetched from the network (cold launch only).
    case downloading
    /// Files are on disk; CoreML models are loading into memory.
    case loading
    /// Model is warm and ready for inference.
    case ready
    /// Load failed permanently; re-launch required.
    case failed
}

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
    /// Decode produced only non-speech annotations (`[BLANK_AUDIO]`, `(heavy
    /// breathing)`, …): Whisper heard the audio but found no words in it. The
    /// session treats this like the all-silence trim case — quiet no-op, not a
    /// failure (planning 0023). Kept distinct from `.emptyTranscription` so the
    /// 0002/0018/0020 feedback surface can later explain "nothing was pasted"
    /// without conflating it with a real decode failure.
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded yet."
        case .transcriptionFailed(let underlying):
            return "Transcription failed: \(underlying.localizedDescription)"
        case .emptyTranscription:
            return "Transcription returned no text."
        case .noSpeechDetected:
            return "No speech was detected in the recording."
        }
    }
}

@MainActor
final class TranscriptionManager {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "transcribe")
    private let modelName: String

    private var whisperKit: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?

    // Published model load state — the menu bar observes this to show an honest
    // "Downloading…" / "Loading…" / "Ready" status during the launch window.
    // Initialized from a synchronous disk check so the first emitted value is
    // already correct when `bind(transcription:)` subscribes in AppDelegate.
    private let loadStateSubject: CurrentValueSubject<ModelLoadState, Never>

    /// Observable publisher of the model load lifecycle.
    var modelLoadState: AnyPublisher<ModelLoadState, Never> {
        loadStateSubject.eraseToAnyPublisher()
    }

    /// Synchronous accessor for the session's model-readiness gate.
    var currentModelLoadState: ModelLoadState { loadStateSubject.value }

    /// User-curated terms that bias decoding toward proper nouns and jargon.
    /// M8 will wire `Settings.customDictionaryTerms` → `setCustomDictionaryTerms`.
    /// Until then, the list is empty; the special-token filter still runs and
    /// no-ops correctly on the empty case (custom-dictionary.md).
    private var customDictionaryTerms: [String] = []

    init(modelName: String = Constants.defaultModel) {
        self.modelName = modelName
        // Synchronous disk check: if the model files are already on disk the user
        // will see "Loading…" (warm launch); otherwise "Downloading model…" (cold).
        let downloadBase = Self.modelDownloadBase()
        let isCached = Self.isModelCached(downloadBase: downloadBase, modelName: modelName)
        loadStateSubject = CurrentValueSubject(isCached ? .loading : .downloading)
    }

    // internal for testability — drives the load state without touching the real
    // model, so session tests can exercise the model-readiness gate.
    func setModelLoadStateForTesting(_ state: ModelLoadState) {
        loadStateSubject.send(state)
    }

    // internal for testability — the model download root. Application Support
    // (not WhisperKit's ~/Documents default) so model downloads never trip the
    // Documents-folder TCC prompt (planning 0010). Pure (no I/O); `loadModel`
    // creates the directory.
    static func modelDownloadBase() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Constants.modelCacheFolderName, isDirectory: true)
    }

    // internal for testability — checks whether the model's CoreML files are
    // already on disk. Used at init time to set the correct initial load state
    // (downloading vs. loading) without an async call. Checks for `AudioEncoder`
    // which WhisperKit requires before `loadModels()` can proceed.
    static func isModelCached(downloadBase: URL, modelName: String) -> Bool {
        // WhisperKit downloads under {base}/models/argmaxinc/whisperkit-coreml/{name}/
        let dir = downloadBase.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml/\(modelName)", isDirectory: true
        )
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("AudioEncoder.mlmodelc").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("AudioEncoder.mlpackage").path)
    }

    /// Idempotent. AppDelegate kicks this off as fire-and-forget at launch.
    /// Coalesces concurrent callers onto the same `Task` so a second `loadModel`
    /// while the first is in-flight doesn't start a second download.
    ///
    /// Emits `ModelLoadState` transitions so the menu bar can show an honest
    /// "Downloading model…" / "Loading…" status:
    ///   Cold launch: .downloading → .loading → .ready
    ///   Warm launch: .loading (already set at init) → .loading → .ready
    ///   Failure:     .downloading/.loading → .failed
    func loadModel() async throws {
        if whisperKit != nil { return }
        if let loadTask {
            _ = try await loadTask.value
            return
        }
        logger.info("Loading WhisperKit model \(self.modelName, privacy: .public)")
        let downloadBase = Self.modelDownloadBase()
        let modelName = self.modelName
        let subject = loadStateSubject  // capture reference; task updates state mid-flight

        let task = Task<WhisperKit, Error> {
            // Download under Application Support (planning 0010).
            try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
            // Phase 1: download or find cached model files. `load: false` skips the
            // in-memory load so we can emit the `.loading` transition before it.
            let wk = try await WhisperKit(model: modelName, downloadBase: downloadBase, load: false)
            // Phase 2: files confirmed on disk — now loading CoreML models into memory.
            subject.send(.loading)
            try await wk.loadModels()
            return wk
        }
        loadTask = task
        do {
            let wk = try await task.value
            whisperKit = wk
            loadStateSubject.send(.ready)
            logger.info("WhisperKit model loaded")
        } catch {
            loadTask = nil
            loadStateSubject.send(.failed)
            logger.error("WhisperKit load failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    func setCustomDictionaryTerms(_ terms: [String]) {
        customDictionaryTerms = terms
    }

    // internal for the eval harness (`TranscriptionEvalTests`, planning 0022) —
    // loads a clip to the 16 kHz float array WhisperKit decodes. Wraps
    // `AudioProcessor` so WhisperKit stays a single import boundary and the test
    // target need not depend on it. Not used in production (live capture supplies
    // samples directly).
    static func loadAudioSamples(fromPath path: String) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
    }

    /// Returns the transcribed text or throws. Throws `.modelNotLoaded` if
    /// `loadModel` hasn't completed (the fail-fast surface — the session logs
    /// and still returns the cycle to `.idle`).
    func transcribe(audioSamples: [Float]) async throws -> String {
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        logger.info("Transcribing \(audioSamples.count, privacy: .public) samples")

        let promptTokens = buildPromptTokens(using: whisperKit)
        let text = try await resolveWithEmptyPromptRetry(promptTokens: promptTokens) { tokens in
            try await self.decode(audioSamples, promptTokens: tokens, using: whisperKit)
        }
        logger.info("Transcribed \(text.count, privacy: .public) chars")
        return text
    }

    // internal for testability — the "a custom-dictionary prompt must only ever
    // *help*" retry rule, lifted out of `transcribe` as a narrow decode seam so
    // it runs without a live model. This is ADR 0001's named-but-unpromoted seam,
    // NOT a `Transcriber` protocol: the caller injects a `decode` closure (the
    // real WhisperKit call in production, a canned string in tests).
    //
    // A small model like `base.en` can occasionally emit empty output when
    // conditioned on a prompt; without the retry, adding a dictionary term could
    // turn a working dictation into a hard `.emptyTranscription` — strictly worse
    // than no dictionary (requirements/custom-dictionary.md). Retry unprompted so
    // the dictionary degrades to neutral. Annotation-only output ("[BLANK_AUDIO]")
    // counts as no-speech for the retry, and classifies as `.noSpeechDetected`
    // at the end (vs `.emptyTranscription` for a truly empty decode — the session
    // treats the former as a quiet no-op and the latter as a loud failure).
    // Logged so prompt-quality regressions stay observable.
    func resolveWithEmptyPromptRetry(
        promptTokens: [Int],
        decode: (_ promptTokens: [Int]) async throws -> String
    ) async throws -> String {
        var text = try await decode(promptTokens)
        if text.isEmpty || Self.isNonSpeechAnnotation(text), !promptTokens.isEmpty {
            logger.warning("Prompted transcription had no speech; retrying without the custom-dictionary prompt")
            text = try await decode([])
        }
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }
        guard !Self.isNonSpeechAnnotation(text) else { throw TranscriptionError.noSpeechDetected }
        return text
    }

    // internal for testability — true when decoded text consists *only* of
    // Whisper's non-speech annotations: bracketed or parenthesized labels like
    // "[BLANK_AUDIO]", "[MUSIC]", "(heavy breathing)", plus any leftover
    // punctuation. The decode gates (`noSpeechThreshold` etc.) do not reliably
    // suppress these — probed on-device with real quiet-room/breath/keyboard
    // clips (planning 0023) — so without this check they paste as literal text.
    // Whole-output classification only: mixed annotation+speech output is left
    // untouched, so dictation that legitimately contains brackets never loses
    // content.
    static func isNonSpeechAnnotation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let stripped = trimmed
            .replacingOccurrences(of: #"\[[^\[\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\([^()]*\)"#, with: "", options: .regularExpression)
        guard stripped != trimmed else { return false }  // no annotation present at all
        return stripped.allSatisfy { $0.isPunctuation || $0.isWhitespace }
    }

    private func decode(_ audioSamples: [Float], promptTokens: [Int], using whisperKit: WhisperKit) async throws -> String {
        // Pin the no-speech / log-prob gate and the temperature-fallback schedule
        // to upstream Whisper defaults (planning 0023). WhisperKit 0.18 already
        // defaults to these, but setting them explicitly keeps the gate from
        // silently regressing if an upstream default changes. Values live in
        // `Constants`, not settings — the user shouldn't reason about them.
        let options = DecodingOptions(
            temperature: Constants.decodingTemperature,
            temperatureIncrementOnFallback: Constants.decodingTemperatureIncrementOnFallback,
            temperatureFallbackCount: Constants.decodingTemperatureFallbackCount,
            promptTokens: promptTokens.isEmpty ? nil : promptTokens,
            compressionRatioThreshold: Constants.compressionRatioThreshold,
            logProbThreshold: Constants.logProbThreshold,
            noSpeechThreshold: Constants.noSpeechThreshold
        )
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
