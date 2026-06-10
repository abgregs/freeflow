import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import os

/// Classification of the system-wide focused UI element, read before posting
/// the synthesized ⌘V (the paste guard, planning 0001). `.unknown` must fail
/// OPEN: AX role reporting is unreliable in web/Electron content, and blocking
/// on ambiguity would regress working dictation. Only a clearly non-editable
/// role skips the paste.
enum FocusedTargetClassification: Equatable {
    case editable
    case nonEditable
    case unknown
}

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

    // internal for testability — pins the focused-target classification so
    // manager tests never reach the real AX read (which would classify
    // whatever the test runner's host happens to have focused at test time).
    // Mirrors `skipPostForTesting`.
    var focusedTargetForTesting: FocusedTargetClassification?

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

    /// Read-only focused-element role check for the paste guard (planning
    /// 0001). Reads the system-wide focused UI element's role/subrole and
    /// classifies it against the editable-role tables. This is read-only AX —
    /// it only gates whether the clipboard + ⌘V paste is attempted and never
    /// becomes the insertion mechanism (the "No AX-API path" decision in
    /// free-flow-pipeline.md rejected AX *writes*).
    func classifyFocusedTarget() -> FocusedTargetClassification {
        if let focusedTargetForTesting { return focusedTargetForTesting }
        // Without trust the AX read fails anyway (kAXErrorAPIDisabled) — fail
        // open and let `postKeyEvent` surface `.notGranted` as today.
        guard currentStatus == .granted else { return .unknown }
        // Under the test flag, never touch the real AX read — the host's
        // live focus would leak into the classification.
        if skipPostForTesting { return .unknown }
        let (role, subrole) = readFocusedElementRole()
        let classification = Self.classifyFocusedTarget(role: role, subrole: subrole)
        switch classification {
        case .unknown:
            insertLogger.info("Paste guard: focused-element role unknown (role=\(role ?? "nil", privacy: .public), subrole=\(subrole ?? "nil", privacy: .public)) — failing open.")
        case .nonEditable:
            insertLogger.info("Paste guard: focused element is not editable (role=\(role ?? "nil", privacy: .public)) — skipping paste.")
        case .editable:
            break
        }
        return classification
    }

    /// Pure editable-role table for the paste guard. Allowlisted roles →
    /// `.editable`; clearly-non-text roles → `.nonEditable`; anything else
    /// (nil, app-custom, under-reported web content) → `.unknown`, which the
    /// caller treats as fail-open. `subrole` is accepted for future tuning but
    /// unused today: the search/secure-field subroles live under `AXTextField`,
    /// which the role allowlist already admits.
    /// internal for testability (the AX read leaf can't be exercised in CI).
    static func classifyFocusedTarget(role: String?, subrole: String?) -> FocusedTargetClassification {
        guard let role else { return .unknown }
        if editableRoles.contains(role) { return .editable }
        if nonEditableRoles.contains(role) { return .nonEditable }
        return .unknown
    }

    // Role strings are the stable AX constants (kAXTextFieldRole etc.); plain
    // literals keep the two tables uniform since several entries (AXWebArea,
    // AXSearchField, AXLink) have no kAX* constant in the HIServices headers.
    private static let editableRoles: Set<String> = [
        "AXTextField",      // includes search/secure fields by subrole
        "AXTextArea",
        "AXComboBox",
        "AXSearchField",    // normally a subrole; admitted as a role defensively
        "AXWebArea"         // web/Electron contenteditable under-reports — treat as editable
    ]

    // Deliberately conservative: only roles that can never accept a paste.
    // AXGroup and anything app-custom stay off this list (fail open instead).
    private static let nonEditableRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXMenuItem",
        "AXLink",
        "AXImage",
        "AXStaticText",
        "AXRow",
        "AXCell",
        "AXTable",
        "AXOutline",
        "AXList",
        "AXSlider",
        "AXDisclosureTriangle"
    ]

    // The OS-call leaf of the paste guard (untestable in CI — reading another
    // app's focused element requires a real Accessibility grant). Any AX error
    // collapses to nil so classification falls through to `.unknown`.
    private func readFocusedElementRole() -> (role: String?, subrole: String?) {
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused
        )
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return (nil, nil)
        }
        // Safe: the CFGetTypeID guard above proves the CF type; `as!` on a CF
        // ref is a bitcast, so the type-id check is the real validation.
        let element = focused as! AXUIElement
        return (
            copyStringAttribute(kAXRoleAttribute, of: element),
            copyStringAttribute(kAXSubroleAttribute, of: element)
        )
    }

    private func copyStringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
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
