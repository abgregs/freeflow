import Foundation
import Testing
@testable import FreeFlow

@Suite("AppState")
struct AppStateTests {
    @MainActor
    @Test("state changes propagate to the observable")
    func stateChangesPropagate() {
        let appState = AppState()
        #expect(appState.state == .idle)
        appState.apply(.recording)
        #expect(appState.state == .recording)
    }

    @MainActor
    @Test("a cycle error becomes a path-redacted message")
    func errorBecomesRedactedMessage() throws {
        // The single choke point: a framework error naming a home path must not
        // carry the account name onto the menu (ADR 0002). If this regresses,
        // the username ships in a screenshot of the menu.
        let appState = AppState()
        let underlying = NSError(
            domain: "WhisperKit", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "load failed at /Users/alice/Documents/model.bin"]
        )
        appState.apply(FreeFlowError.transcription(underlying: underlying))
        let message = try #require(appState.errorMessage)
        #expect(message.contains("/Users/<user>/Documents/model.bin"))
        #expect(!message.contains("/Users/alice"))
    }

    @MainActor
    @Test("starting a new recording clears a stale error")
    func recordingClearsStaleError() {
        let appState = AppState()
        appState.apply(FreeFlowError.textInsertion(underlying: NSError(domain: "x", code: 1)))
        #expect(appState.errorMessage != nil)
        appState.apply(.recording)
        #expect(appState.errorMessage == nil)
    }

    @MainActor
    @Test("a recording-context notice shows during recording and clears when it ends")
    func noticeShownThenClearedOnRecordingEnd() {
        // The live-apply notice is tied to the current recording — it must vanish
        // the moment that recording ends, not linger into the next cycle.
        let appState = AppState()
        appState.apply(.recording)
        appState.apply(notice: "Activation key changed to Left Control. Press it to stop the current recording.")
        #expect(appState.notice != nil)
        appState.apply(.processing)
        #expect(appState.notice == nil)
    }
}
