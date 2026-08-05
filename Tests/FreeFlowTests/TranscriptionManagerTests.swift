import Foundation
import Testing
@testable import FreeFlow

@Suite("TranscriptionManager model gate")
struct TranscriptionManagerGateTests {
    @MainActor
    @Test("transcribe throws .modelNotLoaded when loadModel has not completed")
    func transcribeThrowsWhenModelNotLoaded() async {
        // Per ADR 0001, success-path transcription is integration-tested
        // manually (a real WhisperKit load is too heavy for the unit suite).
        // The fail-fast surface — calling transcribe before the model is
        // loaded — is what `FreeFlowSession` relies on to keep the cycle
        // moving when the user dictates before the model has finished
        // downloading. That contract belongs to a fast unit test.
        let service = TranscriptionManager()
        await #expect(throws: TranscriptionError.self) {
            _ = try await service.transcribe(audioSamples: [0.0, 0.1, 0.2])
        }
    }
}

@Suite("TranscriptionManager model cache location")
struct TranscriptionCacheLocationTests {
    // The model must download under Application Support, never ~/Documents —
    // Documents is TCC-protected, so downloading there triggers a Documents-folder
    // prompt and clutters the user's Documents (planning 0010). This pins the
    // location so a regression to WhisperKit's ~/Documents default fails loudly.
    @MainActor
    @Test("modelDownloadBase resolves under Application Support, not Documents")
    func downloadBaseUnderApplicationSupport() {
        let path = TranscriptionManager.modelDownloadBase().path
        #expect(path.contains("/Library/Application Support/\(Constants.modelCacheFolderName)"))
        #expect(!path.contains("/Documents"))
    }
}

@Suite("TranscriptionManager empty-prompt retry")
struct TranscriptionEmptyPromptRetryTests {
    // The dictionary-can-only-help guarantee (custom-dictionary.md): a prompted
    // decode that comes back empty must retry unprompted, so adding a dictionary
    // term never turns a working dictation into a hard `.emptyTranscription`.
    // Exercised through the narrow decode seam (ADR 0001) — a fake `decode`
    // closure, no live WhisperKit model.

    @MainActor
    @Test("prompted-empty falls back to the unprompted retry and returns its text")
    func promptedEmptyRetriesUnprompted() async throws {
        // Prompted decode degenerates to empty; unprompted yields text. The retry
        // must fire and its text — not an error — is what the user gets.
        let service = TranscriptionManager()
        var calls: [[Int]] = []
        let text = try await service.resolveWithEmptyPromptRetry(promptTokens: [1, 2, 3]) { tokens in
            calls.append(tokens)
            return tokens.isEmpty ? "hello" : ""
        }
        #expect(text == "hello")
        #expect(calls == [[1, 2, 3], []])   // prompted first, then the unprompted retry
    }

    @MainActor
    @Test("a genuinely silent recording (both decodes empty) still throws .emptyTranscription")
    func bothEmptyThrows() async {
        // The retry degrades a bad prompt to neutral, not error — but honest
        // failure must survive: if the audio itself is silent, both decodes are
        // empty and the cycle must still surface `.emptyTranscription`.
        let service = TranscriptionManager()
        await #expect(throws: TranscriptionError.self) {
            _ = try await service.resolveWithEmptyPromptRetry(promptTokens: [1, 2, 3]) { _ in "" }
        }
    }

    @MainActor
    @Test("no prompt: an empty decode throws without a spurious retry")
    func noPromptEmptyThrowsWithoutRetry() async {
        // With no prompt in play there is nothing to degrade to, so an empty
        // decode is an honest empty result — it must not trigger a second call.
        let service = TranscriptionManager()
        var callCount = 0
        await #expect(throws: TranscriptionError.self) {
            _ = try await service.resolveWithEmptyPromptRetry(promptTokens: []) { _ in
                callCount += 1
                return ""
            }
        }
        #expect(callCount == 1)   // no retry when there was no prompt to blame
    }

    @MainActor
    @Test("annotation-only output classifies as .noSpeechDetected, not .emptyTranscription")
    func annotationOnlyThrowsNoSpeechDetected() async {
        // Decode gates don't reliably suppress non-speech — probed on-device:
        // real room tone decodes to "[BLANK_AUDIO]" (planning 0023). That text
        // must never paste, and it must classify as the quiet no-op case (the
        // session skips it silently) rather than the loud .emptyTranscription.
        let service = TranscriptionManager()
        do {
            _ = try await service.resolveWithEmptyPromptRetry(promptTokens: []) { _ in "[BLANK_AUDIO]" }
            Issue.record("expected .noSpeechDetected to be thrown")
        } catch TranscriptionError.noSpeechDetected {
            // expected: quiet no-op classification
        } catch {
            Issue.record("wrong error: \(error) — the session would show the error glyph")
        }
    }

    @MainActor
    @Test("a prompted annotation-only decode triggers the unprompted retry")
    func promptedAnnotationRetriesUnprompted() async throws {
        // Annotation-only is "no speech" for retry purposes too: a prompt that
        // degenerates decoding to "[BLANK_AUDIO]" must get the same second
        // chance as one that degenerates to empty — the dictionary can only help.
        let service = TranscriptionManager()
        var calls: [[Int]] = []
        let text = try await service.resolveWithEmptyPromptRetry(promptTokens: [1, 2, 3]) { tokens in
            calls.append(tokens)
            return tokens.isEmpty ? "hello" : "[BLANK_AUDIO]"
        }
        #expect(text == "hello")
        #expect(calls == [[1, 2, 3], []])
    }
}

@Suite("TranscriptionManager non-speech annotation detector")
struct TranscriptionAnnotationDetectorTests {
    // Pure whole-output classifier for Whisper's non-speech labels. The probe
    // clips (planning 0023) produced exactly these shapes: "[BLANK_AUDIO]"
    // (quiet room), "[MUSIC]" (keyboard), "(heavy breathing)" (breath). A false
    // positive here would silently drop real dictation, so the negative cases
    // matter as much as the positives.

    @MainActor
    @Test("recognizes the observed annotation forms")
    func recognizesObservedForms() {
        #expect(TranscriptionManager.isNonSpeechAnnotation("[BLANK_AUDIO]"))
        #expect(TranscriptionManager.isNonSpeechAnnotation("(heavy breathing)"))
        #expect(TranscriptionManager.isNonSpeechAnnotation("[MUSIC]"))
        #expect(TranscriptionManager.isNonSpeechAnnotation(" [BLANK_AUDIO] "))
    }

    @MainActor
    @Test("recognizes multi-segment and punctuation-trailing annotations")
    func recognizesCompositeForms() {
        // WhisperKit joins segments with spaces, and models often append a
        // period — leftover punctuation must not defeat the classification.
        #expect(TranscriptionManager.isNonSpeechAnnotation("[BLANK_AUDIO] [BLANK_AUDIO]"))
        #expect(TranscriptionManager.isNonSpeechAnnotation("(sighs)."))
        #expect(TranscriptionManager.isNonSpeechAnnotation("[MUSIC] (heavy breathing)"))
    }

    @MainActor
    @Test("never classifies output containing real words")
    func neverEatsRealSpeech() {
        // Mixed annotation+speech keeps the speech — whole-output check only.
        #expect(!TranscriptionManager.isNonSpeechAnnotation("Hello world"))
        #expect(!TranscriptionManager.isNonSpeechAnnotation("Hello (laughs) world"))
        #expect(!TranscriptionManager.isNonSpeechAnnotation("[MUSIC] turn it up"))
    }

    @MainActor
    @Test("empty and annotation-free punctuation are NOT annotations")
    func emptyAndBarePunctuationAreNot() {
        // Empty is `.emptyTranscription`'s territory, and punctuation-only output
        // with no bracketed label present is left alone — classification requires
        // at least one annotation to have matched.
        #expect(!TranscriptionManager.isNonSpeechAnnotation(""))
        #expect(!TranscriptionManager.isNonSpeechAnnotation("   "))
        #expect(!TranscriptionManager.isNonSpeechAnnotation("..."))
    }
}

@Suite("TranscriptionManager prompt-token filter")
struct TranscriptionFilterTests {
    // The custom-dictionary prompt feeds raw token IDs into WhisperKit's
    // `DecodingOptions.promptTokens`. WhisperKit's tokenizer also emits
    // "special" tokens (timestamps, language tags, sentinels) starting at
    // `tokenizer.specialTokens.specialTokenBegin`. Letting one slip into the
    // prompt silently corrupts decoding — the output looks like noise.
    // The filter is the structural guard. Tests pin it on synthetic inputs.

    @MainActor
    @Test("drops tokens at or above specialTokenBegin")
    func dropsAtAndAboveThreshold() {
        let filtered = TranscriptionManager.filterSpecialTokens(
            [0, 5, 100, 50_256, 50_257, 50_258],
            specialTokenBegin: 50_257
        )
        #expect(filtered == [0, 5, 100, 50_256])
    }

    @MainActor
    @Test("passes everything below the threshold through unchanged")
    func passesBelowThreshold() {
        let filtered = TranscriptionManager.filterSpecialTokens(
            [1, 2, 3, 12_345],
            specialTokenBegin: 50_257
        )
        #expect(filtered == [1, 2, 3, 12_345])
    }

    @MainActor
    @Test("empty input returns empty output")
    func emptyInput() {
        #expect(TranscriptionManager.filterSpecialTokens([], specialTokenBegin: 50_257).isEmpty)
    }

    @MainActor
    @Test("threshold of zero filters every token (boundary)")
    func zeroThresholdFiltersAll() {
        // Defensive: if a future tokenizer reports `specialTokenBegin == 0`,
        // we must not pass a single token through (the filter is `<`, not `<=`).
        let filtered = TranscriptionManager.filterSpecialTokens([0, 1, 2, 999], specialTokenBegin: 0)
        #expect(filtered.isEmpty)
    }
}
