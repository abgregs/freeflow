# Architecture: Capabilities

A **Capability** is a small module that owns both:

1. The macOS permission check (granted / denied / unknown — never a lie).
2. The OS call that the permission gates.

There is one capability per required permission. Higher-level managers depend on capabilities, not on the OS APIs directly. **Why:** unifying the check with the use makes permission honesty a structural property — code can't accidentally call `CGEvent.post` without going through `AccessibilityCapability`, which means it can't accidentally skip the check.

This collapses three otherwise-separate concerns into one pattern: permission detection, permission requests, and the use of the permission. The previous-generation design kept these in three different places and paid for it in silent failures and inaccurate onboarding.

## The capabilities

| Capability | What it gates | OS API it wraps |
|---|---|---|
| `MicrophoneCapability` | Audio capture | `AVCaptureDevice.requestAccess(.audio)` + `AVAudioEngine.start()` |
| `InputMonitoringCapability` | Global event taps | `CGEvent.tapCreate(..., options: .listenOnly)` — observe-only, never modifies/consumes input ([0006](../planning/0006_runtime-security-hardening.md)) |
| `AccessibilityCapability` | Posting synthetic events to other apps | `CGEvent.post(...)` (specifically the synthesized ⌘V), plus the read-only focused-element role read behind the paste guard (`AXUIElementCopyAttributeValue` — see [free-flow-pipeline.md](free-flow-pipeline.md)) |

## Common interface

```swift
enum CapabilityStatus: Equatable {
    case granted
    case denied
    case unknown          // dev builds where TCC reporting is unreliable
}

@MainActor
protocol Capability: AnyObject {
    var displayName: String { get }                      // "Accessibility"
    var setupInstructions: String? { get }               // manual-grant steps; nil when auto-promptable
    var status: AnyPublisher<CapabilityStatus, Never> { get }
    var currentStatus: CapabilityStatus { get }          // sync accessor for tests + AppKit gates
    func recheck() async                                  // re-query the status API
    func requestGrant() async                             // Grant button action (see default below)
    func openSystemSettings()                             // for capabilities that can't auto-prompt
}

// Default extension: `setupInstructions` is `nil` and `requestGrant()` calls
// `openSystemSettings()`. Microphone overrides `requestGrant()` to fire the TCC
// auto-prompt (`AVCaptureDevice.requestAccess`); Accessibility and Input
// Monitoring use the default (deep-link to System Settings for a manual add).
```

Each capability also exposes the specific action it gates as a typed method. For example:

```swift
@MainActor
final class AccessibilityCapability: Capability {
    // ... Capability conformance ...

    /// Post a synthetic key event. Throws if the capability is not granted
    /// or if the action silently no-ops (TCC bundle-misidentification case).
    func postKeyEvent(_ event: CGEvent) throws
}
```

**Only `AccessibilityCapability` calls `CGEvent.post`. Only `MicrophoneCapability` starts the audio engine. Only `InputMonitoringCapability` creates the tap.** This is the load-bearing invariant.

## Status detection

Each capability's `recheck()` queries the most authoritative *non-prompting* status API for its permission and maps the result to `CapabilityStatus`:

| Capability | Status API | Mapping |
|---|---|---|
| `MicrophoneCapability` | `AVCaptureDevice.authorizationStatus(for: .audio)` | `.authorized → .granted`; `.denied`/`.restricted → .denied`; `.notDetermined → .unknown` |
| `AccessibilityCapability` | `AXIsProcessTrusted()` | authoritative `Bool` → `.granted` / `.denied` |
| `InputMonitoringCapability` | `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` | true tri-state → `.granted` / `.denied` / `.unknown`, 1:1 |

The mapping functions are `static` and `internal` so tests pin them deterministically without a real TCC grant (see [../conventions/tests.md](../conventions/tests.md)). Input Monitoring deliberately does **not** probe by creating a throwaway `CGEventTap`: that would call `CGEvent.tapCreate` on the main run loop and violate the [threading invariant](threading-invariant.md). The synthesized-action probe described in *Self-detection* below is the **M7 Accessibility bundle-misidentification detector** — a separate concern from status detection.

## Why "no lying"

A `Capability.status` of `.unknown` is the structural answer to "I'm not sure if Accessibility is really granted." It is never lowered to `.granted` by checking a different permission. **Why:** the previous-generation design's `checkAccessibility()` fell back to `checkInputMonitoring()` when the AX check was unreliable for unsigned dev builds. The result: onboarding showed a green checkmark for Accessibility while the actual paste action silently failed. The single hardest bug to diagnose in this app's lineage. `.unknown` makes the gap visible.

When `.unknown` is the answer, the capability's `recheck()` re-queries the most authoritative status API available (see *Status detection* above) and updates `status`. UI shows `.unknown` distinctly from `.denied` — usually as an inline note: "Couldn't confirm grant. Try the feature, or open System Settings."

## How managers consume capabilities

`TextInsertionManager` does not call `CGEvent.post`. It asks `AccessibilityCapability.postKeyEvent(...)`. If the capability throws, the manager surfaces a typed error up to `FreeFlowSession`, which logs and updates state.

```swift
final class TextInsertionManager {
    private let accessibility: AccessibilityCapability
    init(accessibility: AccessibilityCapability) {
        self.accessibility = accessibility
    }

    func insertText(_ text: String) throws {
        // ... clipboard save/write ...
        try accessibility.postKeyEvent(makeCommandVEvent())
        // ... clipboard restore ...
    }
}
```

Same pattern for `HotkeyManager` ↔ `InputMonitoringCapability` (the capability creates the tap; the manager interprets events) and `AudioCaptureManager` ↔ `MicrophoneCapability` (the capability starts the engine; the manager handles buffers).

## Onboarding consumes the capability set

`OnboardingView` does not know about specific capabilities. It iterates `[any Capability]` and renders a row per capability with name, status (from the publisher), and a `Grant` button that calls `requestGrant()` — which triggers the auto-prompt (Microphone) or opens System Settings (Accessibility, Input Monitoring). The window opens whenever **any** capability's status is not `.granted`. The gate predicate is `OnboardingGate.shouldPresent(for:)` and the privacy-pane deep links live in one place as `SystemSettingsPane`.

`OnboardingCoordinator` owns the launch-UI orchestration that this gating implies — the `NSWindow` lifetime, the activation policy, and the dismissal — so `AppDelegate` stays a thin lifecycle shell. Beyond the launch-time `presentIfNeeded()` check, the coordinator **subscribes to every capability's `status` publisher** and re-presents onboarding on a `.granted → !.granted` transition. This is the user-facing surface for **runtime capability degradation**: when the silent-no-op probe (below) flips `AccessibilityCapability.status` to `.denied` mid-session, or the user revokes a grant in System Settings while the app is running, the window re-opens on its own rather than waiting for the next launch. The reverse transition (`.denied → .granted`) is handled by the user re-clicking *Refresh* in the view, not by the coordinator.

**Why:** any new permission added in the future just registers a new capability. Onboarding gets the new row for free. The "onboarding only fires on tap failure" failure mode is structurally impossible — the gating signal is "all capabilities granted," not "managers started successfully."

## Self-detection of TCC bundle misidentification

`AccessibilityCapability.postKeyEvent` can detect the silent-no-op failure mode (where TCC accepts the call but doesn't deliver the event because the bundle ID isn't what TCC expected). The concrete probe (`probe()`) synthesizes a **Shift modifier-down via `.cghidEventTap`**, reads back `CGEventSource.flagsState(.combinedSessionState)`, and expects the shift bit to be set; it then synthesizes the release. Shift is chosen because it's invisible to any text field (no character, no LED), and `.cghidEventTap` matches the production paste tap so a probe failure mirrors a real post failure end-to-end. If the synthesized modifier is never reflected, the action silently no-ops: the capability transitions `status` to `.denied`, logs a diagnostic at `.warning`, and `postKeyEvent` throws `.silentNoOp` rather than posting — even if the OS reported `.granted`. If this technique ever proves unreliable in practice, the documented plan-B is a **CapsLock toggle pair** via `CGEventSource.keyState(.combinedSessionState, key: .capsLock)` (invasive but unambiguous — it toggles a visible LED).

The probe result is cached in `probeConfirmed` so the synthesized round-trip runs at most once per launch: it fires lazily at the **first `postKeyEvent` after the OS view is `.granted`**, then memoizes for subsequent posts. It is **reset whenever `recheck()` observes the OS view drop below `.granted`** (e.g., the user revokes the grant), so a later re-grant re-probes rather than trusting a stale confirmation. `recheck()` also runs the probe directly when it sees `.granted`, so a revoke-then-regrant settles `status` to the probed answer without waiting for the next post.

This is the third anti-pattern (bespoke bundle assembly) gaining a structural detector: a misconfigured bundle now manifests as `AccessibilityCapability.status == .denied`, which `OnboardingCoordinator` observes and surfaces by re-opening onboarding (see *Onboarding consumes the capability set* above), telling the user something is wrong.

## Capabilities and the threading invariant

`InputMonitoringCapability` owns the dedicated event-tap background thread (`com.freeflow.eventtap`, QoS `.userInteractive`). It exposes the tap as a typed event stream that `HotkeyManager` consumes on the main actor (via `Task { @MainActor in ... }`). The threading rule belongs to the capability now, not to a free-floating manager. See [threading-invariant.md](threading-invariant.md).

## Related

- [permissions.md](permissions.md) — user-facing description of the three permissions
- [free-flow-session.md](free-flow-session.md) — the session that consumes the capability-backed managers
- [free-flow-pipeline.md](free-flow-pipeline.md) — traces the capability-failure surface end-to-end (typed `postKeyEvent` errors → `OnboardingCoordinator` re-present → the `FreeFlowSession.errors` publisher → menu bar)
- [threading-invariant.md](threading-invariant.md) — the rule that `InputMonitoringCapability` enforces
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — the lying-check and silent-paste anti-patterns that capabilities make structurally impossible
