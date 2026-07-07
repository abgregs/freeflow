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
final class TranscriptionManager {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "transcribe")
    // Mutable so the model picker (planning 0021) can switch models off-cycle via
    // `switchModel(to:)`; the active model always drives `loadModel` and the cache path.
    private var modelName: String

    private var whisperKit: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?
    // Bumped by every `prepareModelSwitch`; a `loadModel` run only commits its result
    // when its captured generation is still current, so a switch that supersedes an
    // in-flight load (e.g. the launch load) can't clobber the newer model's state.
    private var loadGeneration = 0

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
        let generation = loadGeneration
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
            // A model switch bumped the generation while we loaded — the newer
            // `switchModel` owns `whisperKit`/state now, so drop this stale result.
            guard generation == loadGeneration else { return }
            whisperKit = wk
            loadStateSubject.send(.ready)
            logger.info("WhisperKit model loaded")
        } catch {
            // Don't overwrite a newer switch's state with this superseded failure.
            guard generation == loadGeneration else { throw error }
            loadTask = nil
            loadStateSubject.send(.failed)
            logger.error("WhisperKit load failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    // internal for testability — the model picker's current selection, so session
    // tests can confirm a switch actually re-pointed the manager.
    var currentModelName: String { modelName }

    // internal for testability — the synchronous half of a model switch (planning
    // 0021): swaps the model name and resets `whisperKit`/`loadTask` so the next
    // `loadModel()` won't early-return, re-entering the 0004 load state
    // (`.downloading` if the new model is uncached, else `.loading`) so the menu bar
    // shows the switch honestly. Returns `false` — a no-op — when the requested model
    // is already active. Split from the async reload so the reset and the state
    // transition are unit-testable without loading a real WhisperKit model.
    @discardableResult
    func prepareModelSwitch(to newModelName: String) -> Bool {
        guard newModelName != modelName else { return false }
        loadGeneration += 1
        modelName = newModelName
        whisperKit = nil
        loadTask?.cancel()
        loadTask = nil
        let isCached = Self.isModelCached(downloadBase: Self.modelDownloadBase(), modelName: newModelName)
        loadStateSubject.send(isCached ? .loading : .downloading)
        return true
    }

    // internal for testability — turns the async reload half of `switchModel` into a
    // no-op so `FreeFlowSession` tests can exercise the apply-or-defer routing without
    // loading a real WhisperKit model (mirrors `MicrophoneCapability.skipEngineForTesting`).
    // The synchronous `prepareModelSwitch` still runs, so the re-point and the
    // load-state transition stay observable.
    var skipLoadForTesting = false

    // internal for testability — when set, `transcribe` returns this string instead of
    // calling WhisperKit. Lets session tests exercise post-transcription paths (last-
    // transcript retention, insertion) without a live model.
    var transcribeResultForTesting: String?

    /// Switches to a different curated model and reloads it off-cycle. No-op when the
    /// model is already active. Reuses `loadModel()`'s coalescing after
    /// `prepareModelSwitch` clears the early-return guards. Called from
    /// `FreeFlowSession` only at `.idle` (or on the deferred return to `.idle`), so a
    /// switch can never reload the model out from under an in-flight cycle.
    func switchModel(to newModelName: String) async {
        guard prepareModelSwitch(to: newModelName) else { return }
        if skipLoadForTesting { return }
        try? await loadModel()
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
        if let result = transcribeResultForTesting { return result }
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
    // the dictionary degrades to neutral. A genuinely silent recording still
    // errors honestly (the retry is also empty). Logged so prompt-quality
    // regressions stay observable.
    func resolveWithEmptyPromptRetry(
        promptTokens: [Int],
        decode: (_ promptTokens: [Int]) async throws -> String
    ) async throws -> String {
        var text = try await decode(promptTokens)
        if text.isEmpty, !promptTokens.isEmpty {
            logger.warning("Prompted transcription was empty; retrying without the custom-dictionary prompt")
            text = try await decode([])
        }
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }
        return text
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
