import Foundation
import os
import Sparkle

/// Owns the app's single Sparkle updater (planning 0009). The one place
/// `SPUStandardUpdaterController` is constructed — the updater's background
/// scheduler, first-launch consent prompt, and "Check for Updates…" action all
/// route through here, so there is no second update-check surface (mirrors the
/// one-call-site rule the capabilities layer enforces for OS APIs).
@MainActor
final class UpdaterManager {
    private var controller: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "update")

    /// Whether this build carries a usable EdDSA public key. Read straight from
    /// the bundle, so it is known before `start()` runs and the menu can decide
    /// whether to offer "Check for Updates…" at all.
    static var isConfigured: Bool {
        isUsableEdDSAPublicKey(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    }

    // internal for testability — an Ed25519 public key is 32 bytes, base64-encoded.
    // Rejects nil, the placeholder string, and anything that decodes to the wrong size.
    nonisolated static func isUsableEdDSAPublicKey(_ value: String?) -> Bool {
        guard let value, let data = Data(base64Encoded: value) else { return false }
        return data.count == 32
    }

    /// Constructs and starts the updater. Deferred behind `start()` (rather than
    /// running in `init`) so it only spins up in the real app from
    /// `applicationDidFinishLaunching` — never in `swift test`, which never calls
    /// this. `startingUpdater: true` schedules periodic checks and, on first run,
    /// shows Sparkle's built-in "check for updates automatically?" consent prompt,
    /// keeping the second network behaviour transparent (core-feature.md item 6).
    func start() {
        guard controller == nil else { return }
        // Sparkle validates SUPublicEDKey on start and shows a blocking "updater
        // failed to start" alert when it is invalid. Until the real key is pasted
        // into Info.plist — deliberately deferred to the first release (planning
        // 0027) — the plist holds a placeholder, so don't start at all: no alert,
        // no feed requests. Starts on its own once a valid key is present.
        guard Self.isConfigured else {
            logger.info("Sparkle not started: SUPublicEDKey is missing or a placeholder")
            return
        }
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
