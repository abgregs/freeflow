import Foundation
import Testing
@testable import FreeFlow

/// Manual A/B eval harness for the custom dictionary — **not** a CI test. Runs
/// only when `FREEFLOW_AB_WAV` (a path to a recorded clip) is set, so the normal
/// suite skips it. Feeds ONE fixed clip through transcription with and without the
/// dictionary term, so the prompt is the only variable.
///
/// Writes the result to **`ab-result.txt`** in the project root (and prints it),
/// so you can just open that file instead of digging through test output.
///
/// Usage (clip must live OUTSIDE ~/Desktop|Documents|Downloads — TCC blocks those):
///
///   FREEFLOW_AB_WAV="$PWD/clip.m4a" FREEFLOW_AB_TERM="Vite" \
///     swift test --filter DictionaryEval
///   open -e ab-result.txt          # or just open it in your editor
///
/// Optional: FREEFLOW_AB_MODEL=openai_whisper-base.en  (default: small.en)
@Suite("DictionaryEval")
struct DictionaryEvalTests {
    @MainActor
    @Test(
        "A/B: same clip, dictionary on vs off",
        .enabled(if: ProcessInfo.processInfo.environment["FREEFLOW_AB_WAV"] != nil)
    )
    func dictionaryABOnFixedClip() async throws {
        let env = ProcessInfo.processInfo.environment
        let wavPath = try #require(env["FREEFLOW_AB_WAV"], "set FREEFLOW_AB_WAV to a recorded clip path")
        let term = env["FREEFLOW_AB_TERM"] ?? "Vite"
        let model = env["FREEFLOW_AB_MODEL"] ?? Constants.defaultModel

        let service = TranscriptionManager(modelName: model)
        service.setCustomDictionaryTerms([term])
        try await service.loadModel()
        let r = try await service.evaluateDictionaryPrompt(wavPath: wavPath)

        let box = """
        ┌─ Custom-dictionary A/B ──────────────────────────────
        │ model:         \(model)
        │ clip:          \(wavPath)
        │ term:          "\(term)"
        │ prompt tokens: \(r.promptTokenCount)
        ├─ OFF (no dictionary): \(r.off.isEmpty ? "<empty>" : r.off)
        ├─ ON  (dictionary):    \(r.on.isEmpty ? "<empty>" : r.on)
        ├──────────────────────────────────────────────────────
        │ VERDICT: \(verdict(term: term, off: r.off, on: r.on, promptTokens: r.promptTokenCount))
        └──────────────────────────────────────────────────────
        """

        // Write somewhere trivially viewable (CWD == package root under `swift test`).
        let outPath = env["FREEFLOW_AB_OUT"] ?? "ab-result.txt"
        try? box.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("\n\(box)\n→ also written to \(FileManager.default.currentDirectoryPath)/\(outPath)\n")
    }

    /// Splits the term on commas so a multi-term entry ("Svelte, Vite, Astro") is
    /// judged per word, not as one literal string (the earlier false negatives).
    private func verdict(term: String, off: String, on: String, promptTokens: Int) -> String {
        if promptTokens == 0 { return "EMPTY PROMPT — term tokenized to nothing; dictionary can't apply" }
        if on.isEmpty {
            return "INERT — base.en produced no text on this prompt (in the app the fallback "
                + "silently swaps in the unprompted result). The prompt is not helping here."
        }
        if on == off { return "NO CHANGE — prompt applied but didn't move the output" }
        let words = term.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let landed = words.contains { on.localizedCaseInsensitiveContains($0) && !off.localizedCaseInsensitiveContains($0) }
        return landed
            ? "HELPED ✅ — a dictionary term now appears where it didn't before"
            : "CHANGED but term still absent — partial/odd effect; needs tuning"
    }
}
