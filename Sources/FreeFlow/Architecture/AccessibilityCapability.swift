import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import os

enum AccessibilityCapabilityError: Error, LocalizedError {
    case notGranted
    case silentNoOp

    var errorDescription: String? {
        switch self {
        case .notGranted:
            return "Accessibility permission is not granted; synthesized paste cannot be delivered."
        case .silentNoOp:
            return "Accessibility appears granted but synthesized events are not being delivered. Likely a bundle-misidentification mismatch in TCC — remove the existing entry from System Settings → Privacy & Security → Accessibility, re-add /Applications/FreeFlow.app, and relaunch."
        }
    }
}

@MainActor
final class AccessibilityCapability: Capability {
    let displayName = "Accessibility"
    let setupInstructions: String? =
        "Open System Settings → Privacy & Security → Accessibility, click +, navigate to /Applications/FreeFlow.app, and toggle it on. Then quit and relaunch Free Flow."

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "permissions")
    private let insertLogger = Logger(subsystem: Constants.loggingSubsystem, category: "insert")
    private let subject: CurrentValueSubject<CapabilityStatus, Never>

    // internal for testability — when true, `postKeyEvent` short-circuits both
    // the silent-no-op probe and the real `CGEvent.post`. Mirrors
    // `MicrophoneCapability.skipEngineForTesting`: the test runner often has
    // Accessibility granted (or in CI doesn't, but the trustedness check leaks
    // into the test process either way), so without this the production paste
    // would fire on whatever app was focused at test time.
    var skipPostForTesting = false

    // internal for testability — incremented every time `postKeyEvent` would
    // have posted but `skipPostForTesting` was set. Lets manager tests assert
    // the capability was asked to post the expected number of events without
    // the real `CGEvent.post` firing into the running session.
    private(set) var postedEventCountForTesting = 0

    // internal for testability — drives `status` synchronously without going
    // through `recheck()` (which reads the host TCC state and is non-
    // deterministic across runners). Used to lock the gate in `postKeyEvent`
    // open or closed for a single test. Mirrors `MicrophoneCapability`'s
    // `publishForTest` shape: a single named seam, marked clearly.
    func setStatusForTesting(_ status: CapabilityStatus) {
        probeConfirmed = (status == .granted)
        subject.send(status)
    }

    // Whether the silent-no-op probe has confirmed the capability for this
    // process this launch. Reset whenever the OS view drops below `.granted`
    // (e.g., during a `recheck()` after the user revokes the grant).
    private var probeConfirmed = false

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    init() {
        subject = CurrentValueSubject(Self.readStatus())
    }

    func recheck() async {
        let osStatus = Self.readStatus()
        if osStatus == .granted {
            // Bundle-misidentification backstop: when TCC reports `.granted` we
            // still verify a synthesized round-trip lands. `permissions.md` and
            // `capabilities.md` prescribe this as the structural detector for
            // anti-pattern #3 (a malformed bundle that signs and trusts but
            // silently no-ops on `CGEvent.post`).
            if skipPostForTesting {
                probeConfirmed = true
                update(.granted)
                return
            }
            let delivered = probe()
            probeConfirmed = delivered
            if delivered {
                update(.granted)
            } else {
                insertLogger.warning("Accessibility probe: OS reported granted but synthesized modifier was not observed — downgrading to .denied (bundle misidentification suspected).")
                update(.denied)
            }
        } else {
            probeConfirmed = false
            update(osStatus)
        }
    }

    func openSystemSettings() {
        SystemSettingsPane.accessibility.open()
    }

    /// Post a synthesized `CGEvent`. This is the **only** `CGEvent.post` call
    /// site in the project (load-bearing rule #3 in CLAUDE.md). Throws if
    /// status is not `.granted`, or if the bundle-misidentification probe
    /// indicates the post would silently no-op. Production calls deliver to
    /// `.cghidEventTap` so the event traverses the full input pipeline and
    /// target apps see it as a real keystroke.
    func postKeyEvent(_ event: CGEvent) throws {
        guard subject.value == .granted else {
            throw AccessibilityCapabilityError.notGranted
        }
        if skipPostForTesting {
            postedEventCountForTesting += 1
            return
        }
        if !probeConfirmed {
            let delivered = probe()
            if !delivered {
                insertLogger.warning("Accessibility first-use probe failed; downgrading status and refusing post.")
                update(.denied)
                throw AccessibilityCapabilityError.silentNoOp
            }
            probeConfirmed = true
        }
        event.post(tap: .cghidEventTap)
    }

    // internal for testability — pure round-trip detector for the TCC bundle-
    // misidentification silent-no-op case (anti-pattern #3). Synthesizes a
    // Shift modifier-down, reads `CGEventSource.flagsState(.combinedSessionState)`,
    // and expects the shift bit to be set. Restores by synthesizing the release.
    // Returns true when the OS reflected the synthesized state.
    //
    // Why Shift: invisible to any text field (no character produced, no LED).
    // Why `.cghidEventTap`: matches the production paste tap so a probe failure
    // mirrors a real post failure end-to-end. If this technique ever proves
    // unreliable in practice, the documented plan-B is a CapsLock toggle pair
    // using `CGEventSource.keyState(.combinedSessionState, key: .capsLock)`
    // (invasive but unambiguous — toggles a visible LED).
    func probe() -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true) else {
            return false
        }
        down.flags = .maskShift
        down.post(tap: .cghidEventTap)
        let observed = CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false) {
            up.flags = []
            up.post(tap: .cghidEventTap)
        }
        return observed
    }

    private func update(_ next: CapabilityStatus) {
        guard subject.value != next else { return }
        logger.info("Accessibility status -> \(String(describing: next), privacy: .public)")
        subject.send(next)
    }

    private static func readStatus() -> CapabilityStatus {
        map(isTrusted: AXIsProcessTrusted())
    }

    /// `AXIsProcessTrusted()` reports whether *this running process* is trusted,
    /// so a stale grant for a previous build reads as `.denied` honestly — there
    /// is no false `.granted` from a stale cdhash. The remaining honesty gap is
    /// the bundle-misidentification case, which the `probe()` round-trip catches.
    /// internal for testability (the OS call above can't be exercised in CI).
    static func map(isTrusted: Bool) -> CapabilityStatus {
        isTrusted ? .granted : .denied
    }
}
