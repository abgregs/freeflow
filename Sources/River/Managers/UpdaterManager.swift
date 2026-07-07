import Sparkle

/// Owns the app's single Sparkle updater (planning 0009). The one place
/// `SPUStandardUpdaterController` is constructed — the updater's background
/// scheduler, first-launch consent prompt, and "Check for Updates…" action all
/// route through here, so there is no second update-check surface (mirrors the
/// one-call-site rule the capabilities layer enforces for OS APIs).
@MainActor
final class UpdaterManager {
    private var controller: SPUStandardUpdaterController?

    /// Constructs and starts the updater. Deferred behind `start()` (rather than
    /// running in `init`) so it only spins up in the real app from
    /// `applicationDidFinishLaunching` — never in `swift test`, which never calls
    /// this. `startingUpdater: true` schedules periodic checks and, on first run,
    /// shows Sparkle's built-in "check for updates automatically?" consent prompt,
    /// keeping the second network behaviour transparent (core-feature.md item 6).
    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// User-initiated update check, wired to the "Check for Updates…" menu item.
    /// No-op until `start()` has run.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
