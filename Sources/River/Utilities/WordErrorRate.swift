import Foundation

/// The single source of truth for how transcription accuracy is scored (planning
/// 0022). Word Error Rate = (substitutions + deletions + insertions) / reference
/// words, computed from a word-level edit distance. Pure and model-free so it is
/// unit-tested on synthetic string pairs; the env-gated eval harness feeds it real
/// model output.
///
/// Normalization is decided here and nowhere else, so a scorecard is only ever
/// comparable to another scored by the same rules. See `conventions/tests.md`.
enum WordErrorRate {
    struct Score: Equatable {
        let substitutions: Int
        let deletions: Int
        let insertions: Int
        /// Word count of the *normalized* reference — the denominator, not the raw
        /// string's word count.
        let referenceWordCount: Int

        var errors: Int { substitutions + deletions + insertions }

        /// Errors per reference word. An empty reference is a boundary the ratio
        /// can't express: 0 if the hypothesis is also empty (perfect), else 1.0
        /// (every hypothesis word is a spurious insertion).
        var rate: Double {
            guard referenceWordCount > 0 else { return errors == 0 ? 0 : 1 }
            return Double(errors) / Double(referenceWordCount)
        }
    }

    /// The one normalization rule set: lowercase, drop every character that is not
    /// alphanumeric or whitespace (so `"don't"` → `dont`, `"Hello, world."` →
    /// `hello world`), then split on whitespace, which collapses runs and trims
    /// ends. **Why drop rather than space-replace punctuation:** a contraction is
    /// one spoken word, so `"don't"` must stay one token, not become `don t`.
    static func normalize(_ text: String) -> [String] {
        var scrubbed = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scrubbed.append(scalar)
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                scrubbed.append(" ")
            }
        }
        return String(scrubbed).split(separator: " ").map(String.init)
    }

    /// Word-level Levenshtein between the normalized reference and hypothesis, with
    /// a backtrace that attributes each edit to a substitution, deletion, or
    /// insertion so the scorecard can show *where* a model errs, not just how much.
    static func score(reference: String, hypothesis: String) -> Score {
        let ref = normalize(reference)
        let hyp = normalize(hypothesis)
        let n = ref.count
        let m = hyp.count

        // dp[i][j] = min edits to turn ref[0..<i] into hyp[0..<j].
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }   // i deletions
        for j in 0...m { dp[0][j] = j }   // j insertions
        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    if ref[i - 1] == hyp[j - 1] {
                        dp[i][j] = dp[i - 1][j - 1]
                    } else {
                        dp[i][j] = min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1]) + 1
                    }
                }
            }
        }

        var i = n
        var j = m
        var substitutions = 0
        var deletions = 0
        var insertions = 0
        while i > 0 || j > 0 {
            if i > 0, j > 0, ref[i - 1] == hyp[j - 1] {
                i -= 1
                j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                substitutions += 1
                i -= 1
                j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                deletions += 1
                i -= 1
            } else {
                insertions += 1
                j -= 1
            }
        }

        return Score(
            substitutions: substitutions,
            deletions: deletions,
            insertions: insertions,
            referenceWordCount: n
        )
    }
}
