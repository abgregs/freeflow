import Foundation

/// A transient HUD toast: a user-facing headline plus a recovery hint. Distinct
/// from the lingering menu-row `errorMessage` — this auto-dismisses (planning
/// 0018). Fixed copy per error *kind*, so it carries no user content and needs no
/// redaction (the underlying framework message, which may name a home path, stays
/// on the redacted `errorMessage` path only).
struct ErrorToast: Equatable {
    let headline: String
    let hint: String
}

/// Pure mapping from `FreeFlowError` kind → toast presentation, exactly like
/// `MenuBarPresentation.visual`. Structures the *presentation*, not the error: the
/// typed `FreeFlowError` taxonomy is unchanged (planning 0018). Every case maps, so
/// a new error stage is a compile error here, not a silently missing toast.
enum ErrorToastPresentation {
    static func toast(for error: FreeFlowError) -> ErrorToast {
        switch error {
        case .audioCapture:
            return ErrorToast(
                headline: "Couldn't capture audio",
                hint: "Check that a microphone is connected and not muted, then try again."
            )
        case .transcription:
            return ErrorToast(
                headline: "Couldn't transcribe",
                hint: "No text was produced. Speak a little louder or check your input device."
            )
        case .textInsertion:
            return ErrorToast(
                headline: "Couldn't paste",
                hint: "Click into a text field and try again — Free Flow needs Accessibility access."
            )
        }
    }
}
