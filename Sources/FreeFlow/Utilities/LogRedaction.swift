import Foundation

/// Scrubs personally-identifying data out of strings bound for `os.Logger`
/// before they're logged `privacy: .public`.
///
/// The app's privacy boundary for *user content* (transcribed text, dictionary
/// terms, clipboard contents) is structural: that content is never interpolated
/// into a log line in the first place — only a `.count` is (see
/// `conventions/logging.md`). The remaining leak is contextual: an opaque
/// third-party or OS `error.localizedDescription` can embed a filesystem path
/// like `/Users/<name>/Library/Application Support/FreeFlow/...`, which carries the macOS
/// account name. `redactUserPaths` removes it so error strings stay safe to log
/// publicly — keeping the *reason* a failure happened visible in field bug
/// reports without exposing who the user is. See
/// `decisions/0002-log-redaction-over-debug-flag.md`.
enum LogRedaction {
    /// Replaces any `/Users/<name>` path prefix with `/Users/<user>`,
    /// deterministically and for every occurrence. Idempotent, and a no-op on
    /// strings containing no such path (e.g. app-authored error descriptions),
    /// so it can be applied uniformly at every error-string log site without
    /// per-site judgment about whether the interpolated value is "opaque enough."
    static func redactUserPaths(_ message: String) -> String {
        message.replacingOccurrences(
            of: #"/Users/[^/]+"#,
            with: "/Users/<user>",
            options: .regularExpression
        )
    }
}
