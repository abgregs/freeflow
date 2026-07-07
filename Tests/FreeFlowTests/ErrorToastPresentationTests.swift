import Foundation
import Testing
@testable import FreeFlow

@Suite("ErrorToastPresentation")
struct ErrorToastPresentationTests {
    // The error-kind → toast mapping is a pure function covering every FreeFlowError
    // case (planning 0018 AC3). Each case must yield a non-empty headline and hint;
    // a missing case is a compile error (the switch is exhaustive), and empty copy
    // would ship a blank toast.

    @Test("every FreeFlowError kind maps to a non-empty headline and recovery hint")
    func everyCaseHasHeadlineAndHint() {
        let dummy = NSError(domain: "x", code: 1)
        let errors: [FreeFlowError] = [
            .audioCapture(underlying: dummy),
            .transcription(underlying: dummy),
            .textInsertion(underlying: dummy),
        ]
        for error in errors {
            let toast = ErrorToastPresentation.toast(for: error)
            #expect(!toast.headline.isEmpty)
            #expect(!toast.hint.isEmpty)
        }
    }

    @Test("the three kinds produce distinct headlines")
    func distinctHeadlinesPerKind() {
        // A copy-paste slip that mapped two kinds to the same headline would make the
        // toast diagnostically useless — the whole point of 0018 is an actionable,
        // kind-specific message. Distinct headlines guard against that.
        let dummy = NSError(domain: "x", code: 1)
        let audio = ErrorToastPresentation.toast(for: .audioCapture(underlying: dummy)).headline
        let transcribe = ErrorToastPresentation.toast(for: .transcription(underlying: dummy)).headline
        let paste = ErrorToastPresentation.toast(for: .textInsertion(underlying: dummy)).headline
        #expect(Set([audio, transcribe, paste]).count == 3)
    }

    @Test("toast copy carries no user content from the underlying error")
    func toastCarriesNoUserContent() {
        // The toast is fixed copy per kind, so a home path inside the framework
        // error can't ride onto it (that message stays on the redacted errorMessage
        // path only). Proves the toast never interpolates the underlying description.
        let underlying = NSError(
            domain: "WhisperKit", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "failed at /Users/alice/secret.bin"]
        )
        let toast = ErrorToastPresentation.toast(for: .transcription(underlying: underlying))
        #expect(!toast.headline.contains("/Users/alice"))
        #expect(!toast.hint.contains("/Users/alice"))
    }
}
