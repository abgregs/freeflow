import Foundation
import Testing
@testable import FreeFlow

/// Manual transcription eval harness (planning 0022) — **not** a CI test. Runs
/// only when `FREEFLOW_EVAL_CORPUS` (a path to a local corpus directory) is set,
/// so the normal suite skips it: no model download, no corpus access. Loads one
/// WhisperKit model, runs every clip in the corpus, scores WER against the
/// hand-verified reference, and writes a per-model scorecard.
///
/// The corpus lives OUTSIDE the repo (voice recordings are personal data; the
/// repo is public — anti-pattern #4). A `manifest.json` pairs each clip with its
/// reference transcript and tags. Format and workflow are documented in
/// `docs/conventions/tests.md`. One run per model; the fixed corpus makes runs
/// directly comparable.
///
/// Usage (corpus dir must live OUTSIDE ~/Desktop|Documents|Downloads — TCC blocks
/// those; e.g. `~/free-flow-eval-corpus`):
///
///   FREEFLOW_EVAL_CORPUS="$HOME/free-flow-eval-corpus" \
///     swift test --filter TranscriptionEval
///   open -e eval-openai_whisper-small.en.txt
///
///   Optional: FREEFLOW_EVAL_MODEL=openai_whisper-large-v3-turbo  (default: small.en)
///             FREEFLOW_EVAL_OUT=/tmp/scorecard.txt               (default: ./eval-<model>.txt)
@Suite("TranscriptionEval")
struct TranscriptionEvalTests {
    @MainActor
    @Test(
        "corpus WER + latency scorecard for one model",
        .enabled(if: ProcessInfo.processInfo.environment["FREEFLOW_EVAL_CORPUS"] != nil)
    )
    func evalCorpusScorecard() async throws {
        let env = ProcessInfo.processInfo.environment
        let corpusPath = try #require(env["FREEFLOW_EVAL_CORPUS"], "set FREEFLOW_EVAL_CORPUS to a corpus directory")
        let model = env["FREEFLOW_EVAL_MODEL"] ?? Constants.defaultModel
        let corpus = try EvalCorpus.load(directory: corpusPath)

        let manager = TranscriptionManager(modelName: model)
        let loadStart = Date()
        try await manager.loadModel()
        let loadSeconds = Date().timeIntervalSince(loadStart)

        var rows: [ScorecardRow] = []
        for clip in corpus.clips {
            let samples = try TranscriptionManager.loadAudioSamples(fromPath: corpus.wavPath(for: clip))
            // Mirror the production front-end: the app trims silence before
            // decode (planning 0023), so the eval must too — otherwise silence
            // clips would be judged on un-trimmed audio the app never sees.
            let trimmed = AudioCaptureManager.trimSilence(samples)

            let decodeStart = Date()
            let output: String
            if trimmed.isEmpty {
                output = ""   // the app reads this as "nothing was said"; no decode
            } else {
                do {
                    output = try await manager.transcribe(audioSamples: trimmed)
                } catch TranscriptionError.emptyTranscription {
                    // The no-speech gate (planning 0023) firing is the honest
                    // "empty output" result for this eval, not a harness failure.
                    output = ""
                }
            }
            let latency = Date().timeIntervalSince(decodeStart)

            rows.append(ScorecardRow(clip: clip, output: output, latencySeconds: latency))
        }

        let modelBytes = EvalCorpus.modelSizeOnDisk(modelName: model)
        let card = Scorecard.render(
            model: model,
            corpusPath: corpusPath,
            loadSeconds: loadSeconds,
            modelBytes: modelBytes,
            rows: rows
        )

        let outPath = env["FREEFLOW_EVAL_OUT"] ?? "eval-\(model).txt"
        try? card.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("\n\(card)\n→ also written to \(FileManager.default.currentDirectoryPath)/\(outPath)\n")

        // A silence-tagged clip that produced text is a real regression (0023) —
        // fail the run loudly rather than let a green harness hide it.
        let silenceFailures = rows.filter { $0.clip.isSilence && !$0.output.isEmpty }
        #expect(silenceFailures.isEmpty, "silence-tagged clips produced non-empty output; see the scorecard")
    }
}

// MARK: - Corpus loading

/// A parsed corpus manifest. Kept in the test target (harness-only, no model in
/// the loop) but written to fail with actionable messages when the env var points
/// at a missing or malformed corpus (planning 0022, AC5).
private struct EvalCorpus {
    struct Clip: Decodable {
        let file: String
        let reference: String
        let tags: [String]

        /// Silence fixtures (planning 0023) are scored pass/fail on emptiness, not
        /// WER — an empty output is the correct answer, which WER can't express.
        var isSilence: Bool { tags.contains("silence-heavy") }
    }

    let directory: URL
    let clips: [Clip]

    private struct Manifest: Decodable { let clips: [Clip] }

    static func load(directory path: String) throws -> EvalCorpus {
        let dir = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw EvalCorpusError.missingDirectory(dir.path)
        }
        let manifestURL = dir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw EvalCorpusError.missingManifest(manifestURL.path)
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw EvalCorpusError.malformedManifest(manifestURL.path, error.localizedDescription)
        }
        guard !manifest.clips.isEmpty else {
            throw EvalCorpusError.emptyManifest(manifestURL.path)
        }
        // Fail before loading a model if any referenced clip is missing — a stale
        // manifest should surface immediately, not mid-run.
        for clip in manifest.clips {
            let wav = dir.appendingPathComponent(clip.file)
            guard FileManager.default.fileExists(atPath: wav.path) else {
                throw EvalCorpusError.missingClip(clip.file, dir.path)
            }
        }
        return EvalCorpus(directory: dir, clips: manifest.clips)
    }

    func wavPath(for clip: Clip) -> String {
        directory.appendingPathComponent(clip.file).path
    }

    /// Best-effort on-disk footprint of the model: the size of the download-cache
    /// subfolder whose name matches the model. Reported in the scorecard so the
    /// accuracy/latency numbers can be weighed against download cost.
    @MainActor
    static func modelSizeOnDisk(modelName: String) -> Int64 {
        let base = TranscriptionManager.modelDownloadBase()
        guard let modelDir = findModelDirectory(named: modelName, under: base) else { return 0 }
        return directorySize(at: modelDir)
    }

    private static func findModelDirectory(named modelName: String, under base: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == modelName {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { return url }
        }
        return nil
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

private enum EvalCorpusError: Error, LocalizedError {
    case missingDirectory(String)
    case missingManifest(String)
    case malformedManifest(String, String)
    case emptyManifest(String)
    case missingClip(String, String)

    var errorDescription: String? {
        switch self {
        case .missingDirectory(let path):
            return "FREEFLOW_EVAL_CORPUS directory does not exist: \(path)"
        case .missingManifest(let path):
            return "corpus is missing its manifest.json (expected at \(path)); see docs/conventions/tests.md"
        case .malformedManifest(let path, let reason):
            return "manifest.json could not be parsed (\(path)): \(reason). Expected {\"clips\": [{\"file\", \"reference\", \"tags\"}]}"
        case .emptyManifest(let path):
            return "manifest.json lists no clips (\(path)); add at least one entry"
        case .missingClip(let file, let dir):
            return "manifest references a clip that is not in the corpus: \(file) (looked in \(dir))"
        }
    }
}

// MARK: - Scorecard

private struct ScorecardRow {
    let clip: EvalCorpus.Clip
    let output: String
    let latencySeconds: Double

    var score: WordErrorRate.Score {
        WordErrorRate.score(reference: clip.reference, hypothesis: output)
    }
}

private enum Scorecard {
    static func render(
        model: String,
        corpusPath: String,
        loadSeconds: Double,
        modelBytes: Int64,
        rows: [ScorecardRow]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let scored = rows.filter { !$0.clip.isSilence }
        let silence = rows.filter { $0.clip.isSilence }

        let totalErrors = scored.reduce(0) { $0 + $1.score.errors }
        let totalRefWords = scored.reduce(0) { $0 + $1.score.referenceWordCount }
        let aggregateWER = totalRefWords > 0 ? Double(totalErrors) / Double(totalRefWords) : 0
        let meanWER = scored.isEmpty ? 0 : scored.reduce(0.0) { $0 + $1.score.rate } / Double(scored.count)
        let silencePass = silence.filter { $0.output.isEmpty }.count
        let totalDecode = rows.reduce(0.0) { $0 + $1.latencySeconds }

        var lines: [String] = []
        lines.append("Free Flow transcription eval — \(model)")
        lines.append("generated:  \(formatter.string(from: Date()))")
        lines.append("corpus:     \(corpusPath)  (\(rows.count) clips)")
        lines.append("model load: \(seconds(loadSeconds))")
        lines.append("model size: \(megabytes(modelBytes))")
        lines.append("")
        lines.append(row("CLIP", "TAGS", "REF", "WER", "LATENCY", "RESULT"))
        lines.append(String(repeating: "-", count: 78))
        for r in rows {
            let tags = r.clip.tags.joined(separator: ",")
            if r.clip.isSilence {
                lines.append(row(
                    r.clip.file, tags, "0", "—",
                    seconds(r.latencySeconds),
                    r.output.isEmpty ? "empty ✓" : "LEAK ✗"
                ))
            } else {
                let s = r.score
                lines.append(row(
                    r.clip.file, tags, String(s.referenceWordCount),
                    String(format: "%.3f", s.rate),
                    seconds(r.latencySeconds),
                    "S\(s.substitutions) D\(s.deletions) I\(s.insertions)"
                ))
            }
        }
        lines.append("")
        lines.append("AGGREGATE")
        lines.append("  clips scored (WER):  \(scored.count)")
        lines.append("  aggregate WER:       \(String(format: "%.4f", aggregateWER))   (errors / reference words)")
        lines.append("  mean per-clip WER:   \(String(format: "%.4f", meanWER))")
        lines.append("  silence clips:       \(silence.count)   (\(silencePass) pass / \(silence.count - silencePass) fail)")
        lines.append("  total decode time:   \(seconds(totalDecode))")
        return lines.joined(separator: "\n")
    }

    private static func row(_ cols: String...) -> String {
        let widths = [30, 16, 4, 8, 9, 11]
        return zip(cols, widths).map { col, width in
            col.count >= width ? col + " " : col.padding(toLength: width, withPad: " ", startingAt: 0)
        }.joined()
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }

    private static func megabytes(_ bytes: Int64) -> String {
        bytes == 0 ? "unknown" : String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
