import AVFoundation
import Combine
import CoreGraphics
import IOKit.hid
import Testing
@testable import FreeFlow

/// Test double for protocol-contract, reactivity, and gate tests. Lets a test
/// set status without touching the host machine's real TCC grants, so the suite
/// is deterministic on any machine (per docs/conventions/tests.md).
@MainActor
final class FakeCapability: Capability {
    let displayName: String
    let setupInstructions: String?
    private let subject: CurrentValueSubject<CapabilityStatus, Never>

    private(set) var requestGrantCount = 0
    private(set) var recheckCount = 0
    private(set) var openSystemSettingsCount = 0

    init(displayName: String = "Fake", setupInstructions: String? = nil, status: CapabilityStatus = .denied) {
        self.displayName = displayName
        self.setupInstructions = setupInstructions
        self.subject = CurrentValueSubject(status)
    }

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    func set(_ status: CapabilityStatus) { subject.send(status) }

    func recheck() async { recheckCount += 1 }
    func requestGrant() async { requestGrantCount += 1 }
    func openSystemSettings() { openSystemSettingsCount += 1 }
}

@Suite("Capability protocol contract")
struct CapabilityProtocolTests {
    @MainActor
    @Test("default requestGrant() routes to openSystemSettings()")
    func defaultRequestGrantOpensSettings() async {
        // The default Grant action for a non-auto-promptable permission must be
        // "open System Settings" — that is the only path a self-signed build has.
        final class DefaultGrantCapability: Capability {
            let displayName = "Default"
            let subject = CurrentValueSubject<CapabilityStatus, Never>(.denied)
            var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
            var currentStatus: CapabilityStatus { subject.value }
            private(set) var openedSettings = false
            func recheck() async {}
            func openSystemSettings() { openedSettings = true }
        }
        let capability = DefaultGrantCapability()
        await capability.requestGrant()
        #expect(capability.openedSettings)
    }

    @MainActor
    @Test("setupInstructions defaults to nil when unspecified")
    func setupInstructionsDefaultsNil() {
        // Auto-promptable capabilities (Microphone) carry no manual instructions;
        // the default must be nil so the onboarding row hides the instruction text.
        final class BareCapability: Capability {
            let displayName = "Bare"
            let subject = CurrentValueSubject<CapabilityStatus, Never>(.denied)
            var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
            var currentStatus: CapabilityStatus { subject.value }
            func recheck() async {}
            func openSystemSettings() {}
        }
        #expect(BareCapability().setupInstructions == nil)
    }
}

@Suite("Capability status publisher")
struct CapabilityPublisherTests {
    @MainActor
    @Test("status publisher replays current value then emits on change")
    func publisherReplaysThenEmits() {
        // OnboardingView relies on the publisher firing for live status updates;
        // a publisher that never emits would freeze the UI on the launch value.
        let capability = FakeCapability(status: .denied)
        var received: [CapabilityStatus] = []
        let token = capability.status.sink { received.append($0) }
        capability.set(.granted)
        token.cancel()
        #expect(received == [.denied, .granted])
    }
}

@Suite("Onboarding gate")
struct OnboardingGateTests {
    @MainActor
    @Test("gate opens when any capability is denied")
    func opensWhenAnyDenied() {
        let caps: [any Capability] = [
            FakeCapability(status: .granted),
            FakeCapability(status: .denied),
            FakeCapability(status: .granted)
        ]
        #expect(OnboardingGate.shouldPresent(for: caps))
    }

    @MainActor
    @Test("gate opens when any capability is unknown")
    func opensWhenAnyUnknown() {
        // .unknown is not .granted, so an unconfirmable grant must still open
        // onboarding rather than silently passing as good.
        let caps: [any Capability] = [
            FakeCapability(status: .granted),
            FakeCapability(status: .unknown)
        ]
        #expect(OnboardingGate.shouldPresent(for: caps))
    }

    @MainActor
    @Test("gate stays closed only when every capability is granted")
    func closedWhenAllGranted() {
        let caps: [any Capability] = [
            FakeCapability(status: .granted),
            FakeCapability(status: .granted),
            FakeCapability(status: .granted)
        ]
        #expect(!OnboardingGate.shouldPresent(for: caps))
    }

    @MainActor
    @Test("gate re-evaluates after a denied capability becomes granted")
    func reevaluatesAfterGrant() {
        // Encodes the Refresh/Grant flow: once the last permission is granted,
        // the gate must report the user is done.
        let last = FakeCapability(status: .denied)
        let caps: [any Capability] = [FakeCapability(status: .granted), last]
        #expect(OnboardingGate.shouldPresent(for: caps))
        last.set(.granted)
        #expect(!OnboardingGate.shouldPresent(for: caps))
    }
}

@Suite("Capability status mapping")
struct CapabilityStatusMappingTests {
    // Lock the honest mappings so a regression — lowering a not-determined or
    // unconfirmable state to .granted, or a promptable state to a hard .denied —
    // fails the suite. These are pure functions, fully deterministic, and are the
    // structural guard behind capabilities.md "no lying".

    @MainActor
    @Test("Accessibility: trusted -> granted, untrusted -> denied")
    func accessibilityMapping() {
        #expect(AccessibilityCapability.map(isTrusted: true) == .granted)
        #expect(AccessibilityCapability.map(isTrusted: false) == .denied)
    }

    @MainActor
    @Test("Microphone: authorized -> granted, denied/restricted -> denied, notDetermined -> unknown")
    func microphoneMapping() {
        #expect(MicrophoneCapability.map(.authorized) == .granted)
        #expect(MicrophoneCapability.map(.denied) == .denied)
        #expect(MicrophoneCapability.map(.restricted) == .denied)
        #expect(MicrophoneCapability.map(.notDetermined) == .unknown)
    }

    @MainActor
    @Test("Input Monitoring: granted/denied/unknown map 1:1 — never a lie")
    func inputMonitoringMapping() {
        #expect(InputMonitoringCapability.map(kIOHIDAccessTypeGranted) == .granted)
        #expect(InputMonitoringCapability.map(kIOHIDAccessTypeDenied) == .denied)
        #expect(InputMonitoringCapability.map(kIOHIDAccessTypeUnknown) == .unknown)
    }
}

@Suite("Real capability contract")
struct RealCapabilityContractTests {
    // These assert host-independent contract properties only. The OS-call leaf
    // (real TCC status) cannot be exercised in CI without a grant, so it is not
    // asserted here (per docs/conventions/tests.md).

    @MainActor
    @Test("Accessibility and Input Monitoring expose manual setup instructions")
    func manualCapabilitiesHaveInstructions() {
        #expect(AccessibilityCapability().setupInstructions != nil)
        #expect(InputMonitoringCapability().setupInstructions != nil)
    }

    @MainActor
    @Test("Microphone has no manual instructions because it auto-prompts")
    func microphoneHasNoInstructions() {
        #expect(MicrophoneCapability().setupInstructions == nil)
    }

    @MainActor
    @Test("display names match the System Settings panes the user must visit")
    func displayNames() {
        #expect(AccessibilityCapability().displayName == "Accessibility")
        #expect(MicrophoneCapability().displayName == "Microphone")
        #expect(InputMonitoringCapability().displayName == "Input Monitoring")
    }

    @MainActor
    @Test("real capabilities never report a status outside the honest enum")
    func statusIsAlwaysAValidCase() async {
        // Guards against a future regression that returns an out-of-band value;
        // recheck must always settle on one of granted/denied/unknown.
        let caps: [any Capability] = [
            AccessibilityCapability(),
            MicrophoneCapability(),
            InputMonitoringCapability()
        ]
        for capability in caps {
            await capability.recheck()
            let status = capability.currentStatus
            #expect(status == .granted || status == .denied || status == .unknown)
        }
    }
}

@Suite("AccessibilityCapability focused-target classification")
struct FocusedTargetClassificationTests {
    // The pure editable-role table behind the paste guard (planning 0001).
    // These tests are the regression guard for acceptance criterion 4: the
    // classification is pinned with no AX grant, while the OS-call leaf
    // (reading the real focused element) stays untestable in CI.

    @MainActor
    @Test("editable roles classify as .editable", arguments: [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"
    ])
    func editableRoles(role: String) {
        #expect(AccessibilityCapability.classifyFocusedTarget(role: role, subrole: nil) == .editable)
    }

    @MainActor
    @Test("clearly non-editable roles classify as .nonEditable", arguments: [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXMenuButton", "AXMenuItem", "AXLink", "AXImage", "AXStaticText",
        "AXRow", "AXCell", "AXTable", "AXOutline", "AXList", "AXSlider",
        "AXDisclosureTriangle"
    ])
    func nonEditableRoles(role: String) {
        #expect(AccessibilityCapability.classifyFocusedTarget(role: role, subrole: nil) == .nonEditable)
    }

    @MainActor
    @Test("unrecognized or missing roles classify as .unknown (fail open)")
    func unknownRoles() {
        // AX role reporting is unreliable in web/Electron content. Anything we
        // can't positively classify must be .unknown so the guard attempts the
        // paste — failing closed would regress working dictation.
        #expect(AccessibilityCapability.classifyFocusedTarget(role: nil, subrole: nil) == .unknown)
        #expect(AccessibilityCapability.classifyFocusedTarget(role: "AXUnheardOfRole", subrole: nil) == .unknown)
        #expect(AccessibilityCapability.classifyFocusedTarget(role: "AXGroup", subrole: nil) == .unknown)
    }

    @MainActor
    @Test("subrole does not override the role-based decision today")
    func subroleIsInertForV1() {
        // Pins the v1 contract: search/secure fields are AXTextField subroles,
        // already admitted by role, and no subrole demotes an editable role.
        // If a subrole-based rule lands later, this test should change with it.
        #expect(AccessibilityCapability.classifyFocusedTarget(role: "AXTextField", subrole: "AXSearchField") == .editable)
        #expect(AccessibilityCapability.classifyFocusedTarget(role: "AXTextField", subrole: "AXSecureTextField") == .editable)
        #expect(AccessibilityCapability.classifyFocusedTarget(role: nil, subrole: "AXSearchField") == .unknown)
    }

    @MainActor
    @Test("classification falls open to .unknown when status is below .granted")
    func failsOpenWithoutGrant() {
        // Without trust the AX read can't work; the guard must not block the
        // paste attempt — postKeyEvent surfaces .notGranted as today.
        let capability = AccessibilityCapability()
        capability.setStatusForTesting(.denied)
        #expect(capability.classifyFocusedTarget() == .unknown)
    }

    @MainActor
    @Test("focusedTargetForTesting pins the classification")
    func testSeamPinsClassification() {
        let capability = AccessibilityCapability()
        capability.setStatusForTesting(.granted)
        capability.focusedTargetForTesting = .nonEditable
        #expect(capability.classifyFocusedTarget() == .nonEditable)
    }
}

@Suite("InputMonitoringCapability event decoding")
struct InputMonitoringDecodeTests {
    // The decode helper is the only CGEvent → TapEvent surface. Tests synthesize
    // events here instead of through a real CGEventTap (no permission in CI).

    @MainActor
    @Test("flagsChanged event decodes to TapEvent.flagsChanged with keyCode and flags")
    func decodesFlagsChanged() {
        let event = CGEvent(source: nil)!
        event.type = .flagsChanged
        event.setIntegerValueField(.keyboardEventKeycode, value: 62)
        event.flags = .maskControl

        let decoded = InputMonitoringCapability.decode(event)
        #expect(decoded == .flagsChanged(keyCode: 62, flags: .maskControl))
    }

    @MainActor
    @Test("tapDisabledByTimeout decodes to .tapDisabled (self-heal signal)")
    func decodesTapDisabledByTimeout() {
        let event = CGEvent(source: nil)!
        event.type = .tapDisabledByTimeout
        #expect(InputMonitoringCapability.decode(event) == .tapDisabled)
    }

    @MainActor
    @Test("tapDisabledByUserInput decodes to .tapDisabled")
    func decodesTapDisabledByUserInput() {
        let event = CGEvent(source: nil)!
        event.type = .tapDisabledByUserInput
        #expect(InputMonitoringCapability.decode(event) == .tapDisabled)
    }

    @MainActor
    @Test("unrelated event types decode to nil")
    func decodesUnrelatedAsNil() {
        // Hold the tap surface tight: we listen on `.flagsChanged` only;
        // anything else getting through would be a regression in the mask.
        let event = CGEvent(source: nil)!
        event.type = .keyDown
        #expect(InputMonitoringCapability.decode(event) == nil)
    }
}
