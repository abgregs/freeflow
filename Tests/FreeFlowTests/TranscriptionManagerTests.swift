import Foundation
import Testing
@testable import FreeFlow

@Suite("TranscriptionManager model load state")
struct TranscriptionManagerLoadStateTests {
    // planning 0004: the initial load state is set from a synchronous disk check
    // at init time so the menu bar shows the right label before `loadModel()` runs.

    @MainActor
    @Test("initial modelLoadState is downloading or loading (never ready before loadModel)")
    func initialLoadStateIsNotReady() {
        // On a machine without the model cached (CI), state is .downloading.
        // On a machine with the cache, state is .loading. Either is correct —
        // neither is .ready, which would be a lie before the model is warm.
        let mgr = TranscriptionManager()
        #expect(mgr.currentModelLoadState != .ready)
        #expect(mgr.currentModelLoadState != .failed)
    }

    @MainActor
    @Test("setModelLoadStateForTesting drives currentModelLoadState")
    func testSeamDrivesState() {
        let mgr = TranscriptionManager()
        mgr.setModelLoadStateForTesting(.ready)
        #expect(mgr.currentModelLoadState == .ready)
        mgr.setModelLoadStateForTesting(.loading)
        #expect(mgr.currentModelLoadState == .loading)
    }

    @MainActor
    @Test("modelLoadState publisher emits the current value on subscribe")
    func publisherEmitsCurrentValueOnSubscribe() {
        let mgr = TranscriptionManager()
        var received: [ModelLoadState] = []
        let token = mgr.modelLoadState.sink { received.append($0) }
        defer { token.cancel() }
        // CurrentValueSubject delivers the current value immediately on subscribe.
        #expect(received.count == 1)
        #expect(received.first == mgr.currentModelLoadState)
    }

    @MainActor
    @Test("isModelCached returns false when the model directory does not exist")
    func isModelCachedFalseWhenMissing() {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ff-test-\(UUID().uuidString)", isDirectory: true)
        #expect(!TranscriptionManager.isModelCached(downloadBase: temp, modelName: "openai_whisper-small.en"))
    }
}

@Suite("TranscriptionManager model switch")
struct TranscriptionManagerModelSwitchTests {
    // planning 0021: the picker switches models off-cycle. `prepareModelSwitch` is the
    // synchronous half — it re-points the manager and re-enters the 0004 load window
    // so the menu bar can't keep showing "Ready" for a model that isn't loaded yet.

    @MainActor
    @Test("prepareModelSwitch re-points the model and re-enters the load window")
    func switchRepointsAndReloads() {
        let mgr = TranscriptionManager(modelName: "openai_whisper-small.en")
        mgr.setModelLoadStateForTesting(.ready)   // pretend the first model is warm
        let changed = mgr.prepareModelSwitch(to: "openai_whisper-base.en")
        #expect(changed)
        #expect(mgr.currentModelName == "openai_whisper-base.en")
        // Re-entered the honest load window — never left showing "Ready" for a model
        // that is not actually loaded (planning 0004/0021 AC3). On CI the new model is
        // uncached (.downloading); with a cache it's .loading — either is honest.
        #expect(mgr.currentModelLoadState != .ready)
        #expect(mgr.currentModelLoadState != .failed)
    }

    @MainActor
    @Test("prepareModelSwitch to the already-active model is a no-op")
    func switchToSameModelIsNoOp() {
        let mgr = TranscriptionManager(modelName: "openai_whisper-small.en")
        mgr.setModelLoadStateForTesting(.ready)
        let changed = mgr.prepareModelSwitch(to: "openai_whisper-small.en")
        #expect(!changed)
        #expect(mgr.currentModelName == "openai_whisper-small.en")
        #expect(mgr.currentModelLoadState == .ready)   // untouched — no needless reload
    }
}

@Suite("Curated model list")
struct CuratedModelListTests {
    // planning 0021: the picker is driven by `Constants.curatedModels`. This pins the
    // load-bearing invariants — the default is selectable and every entry is complete —
    // so a dropped default or a half-filled row is a failing test, not silent drift.

    @MainActor
    @Test("the curated list includes the default model")
    func includesDefault() {
        #expect(Constants.curatedModels.contains { $0.name == Constants.defaultModel })
    }

    @MainActor
    @Test("every entry has a name, label, and hint")
    func entriesAreComplete() {
        for model in Constants.curatedModels {
            #expect(!model.name.isEmpty)
            #expect(!model.label.isEmpty)
            #expect(!model.hint.isEmpty)
        }
    }

    @MainActor
    @Test("model names are unique (Picker tags must not collide)")
    func namesAreUnique() {
        let names = Constants.curatedModels.map(\.name)
        #expect(Set(names).count == names.count)
    }
}

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
