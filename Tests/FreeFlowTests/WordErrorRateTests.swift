import Foundation
import Testing
@testable import FreeFlow

// The pure WER scorer is the unit-tested core of the eval harness (planning
// 0022): if these normalization and edit-distance rules drift, every scorecard
// silently means something different. No model, no corpus, runs in the default
// suite.

@Suite("WordErrorRate normalization")
struct WordErrorRateNormalizationTests {
    @Test("lowercases and splits on whitespace")
    func lowercasesAndSplits() {
        #expect(WordErrorRate.normalize("Hello World") == ["hello", "world"])
    }

    @Test("collapses runs of whitespace and trims ends")
    func collapsesWhitespace() {
        #expect(WordErrorRate.normalize("  the   quick \t brown\n") == ["the", "quick", "brown"])
    }

    @Test("strips punctuation without splitting contractions")
    func stripsPunctuationKeepingContractions() {
        // A contraction is one spoken word: "don't" must stay one token, and
        // trailing punctuation must not leak into the comparison.
        #expect(WordErrorRate.normalize("Don't, please!") == ["dont", "please"])
    }

    @Test("empty and punctuation-only strings normalize to no words")
    func emptyNormalizesToNothing() {
        #expect(WordErrorRate.normalize("").isEmpty)
        #expect(WordErrorRate.normalize("  ...  !!! ").isEmpty)
    }
}

@Suite("WordErrorRate scoring")
struct WordErrorRateScoringTests {
    @Test("identical strings score zero")
    func identicalIsZero() {
        let score = WordErrorRate.score(reference: "the quick brown fox", hypothesis: "the quick brown fox")
        #expect(score.errors == 0)
        #expect(score.rate == 0)
    }

    @Test("a single substitution counts as one substitution")
    func oneSubstitution() {
        let score = WordErrorRate.score(reference: "the quick brown fox", hypothesis: "the slow brown fox")
        #expect(score.substitutions == 1)
        #expect(score.deletions == 0)
        #expect(score.insertions == 0)
        #expect(score.rate == 0.25)   // 1 error / 4 reference words
    }

    @Test("a dropped word counts as one deletion")
    func oneDeletion() {
        let score = WordErrorRate.score(reference: "the quick brown fox", hypothesis: "the quick fox")
        #expect(score.deletions == 1)
        #expect(score.substitutions == 0)
        #expect(score.insertions == 0)
    }

    @Test("an added word counts as one insertion")
    func oneInsertion() {
        let score = WordErrorRate.score(reference: "the quick brown fox", hypothesis: "the quick brown red fox")
        #expect(score.insertions == 1)
        #expect(score.substitutions == 0)
        #expect(score.deletions == 0)
    }

    @Test("mixed edits are attributed to the right operation counts")
    func mixedEdits() {
        // "the quick brown fox" → "a quick brown": substitute the→a, delete fox.
        let score = WordErrorRate.score(reference: "the quick brown fox", hypothesis: "a quick brown")
        #expect(score.substitutions == 1)
        #expect(score.deletions == 1)
        #expect(score.insertions == 0)
        #expect(score.rate == 0.5)   // 2 errors / 4 reference words
    }

    @Test("normalization means casing and punctuation are not errors")
    func normalizationIsNotAnError() {
        let score = WordErrorRate.score(
            reference: "Open the settings panel.",
            hypothesis: "open the Settings panel"
        )
        #expect(score.errors == 0)
    }

    @Test("empty reference with empty hypothesis is a perfect score")
    func bothEmptyIsPerfect() {
        let score = WordErrorRate.score(reference: "", hypothesis: "")
        #expect(score.referenceWordCount == 0)
        #expect(score.rate == 0)
    }

    @Test("empty reference with output is fully wrong (all insertions)")
    func emptyReferenceWithOutputIsWrong() {
        let score = WordErrorRate.score(reference: "", hypothesis: "unexpected words here")
        #expect(score.insertions == 3)
        #expect(score.rate == 1)   // boundary: empty reference, non-empty hypothesis
    }

    @Test("dropping every reference word is 100% WER")
    func allDeletedIsFullRate() {
        let score = WordErrorRate.score(reference: "one two three", hypothesis: "")
        #expect(score.deletions == 3)
        #expect(score.rate == 1)
    }
}
