import Testing
@testable import FreeFlow

@Suite("LogRedaction")
struct LogRedactionTests {
    // The load-bearing intent: an opaque framework error that names a home path
    // must not carry the account name into a `privacy: .public` log line. If the
    // regex breaks, the account name leaks — this test fails before it ships.
    @Test("redacts a home path, preserving the surrounding message and tail")
    func redactsHomePath() {
        let input = "Could not load model at /Users/alice/Documents/huggingface/models/base.en"
        #expect(
            LogRedaction.redactUserPaths(input)
                == "Could not load model at /Users/<user>/Documents/huggingface/models/base.en"
        )
    }

    // Justifies applying the helper uniformly at every error-string site: on an
    // app-authored error with no path it must change nothing.
    @Test("is a no-op on a string with no user path")
    func noOpWithoutPath() {
        let input = "No audio was captured (engine may have failed to start)."
        #expect(LogRedaction.redactUserPaths(input) == input)
    }

    @Test("redacts every occurrence and any account name, not just the current user")
    func redactsEveryOccurrence() {
        let input = "/Users/bob/a.txt -> /Users/carol/b.txt"
        #expect(LogRedaction.redactUserPaths(input) == "/Users/<user>/a.txt -> /Users/<user>/b.txt")
    }

    @Test("is idempotent")
    func idempotent() {
        let once = LogRedaction.redactUserPaths("/Users/dave/x")
        #expect(LogRedaction.redactUserPaths(once) == once)
    }
}
