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
            try await WhisperKit(model: modelName)
        }
        loadTask = task
        do {
            let wk = try await task.value
            whisperKit = wk
            logger.info("WhisperKit model loaded")
        } catch {
            loadTask = nil
            logger.error("WhisperKit load failed: \(error.localizedDescription, privacy: .public)")
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
        let options = DecodingOptions(
            promptTokens: promptTokens.isEmpty ? nil : promptTokens
        )

        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
        } catch {
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }

        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }
        logger.info("Transcribed \(text.count, privacy: .public) chars")
        return text
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
