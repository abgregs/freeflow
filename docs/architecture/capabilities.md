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
| `InputMonitoringCapability` | Global event taps | `CGEvent.tapCreate(...)` |
| `AccessibilityCapability` | Posting synthetic events to other apps | `CGEvent.post(...)` (specifically the synthesized ⌘V) |

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
    var status: AnyPublisher<CapabilityStatus, Never> { get }
    var currentStatus: CapabilityStatus { get }          // sync accessor for tests + AppKit gates
    func recheck() async                                  // re-query TCC / try the action
    func openSystemSettings()                             // for capabilities that can't auto-prompt
}
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

## Why "no lying"

A `Capability.status` of `.unknown` is the structural answer to "I'm not sure if Accessibility is really granted." It is never lowered to `.granted` by checking a different permission. **Why:** the previous-generation design's `checkAccessibility()` fell back to `checkInputMonitoring()` when the AX check was unreliable for unsigned dev builds. The result: onboarding showed a green checkmark for Accessibility while the actual paste action silently failed. The single hardest bug to diagnose in this app's lineage. `.unknown` makes the gap visible.

When `.unknown` is the answer, the capability exposes a `recheck()` that performs the most authoritative check available (typically attempting the gated action with a synthesized no-op) and updates `status`. UI shows `.unknown` distinctly from `.denied` — usually as an inline note: "Couldn't confirm grant. Try the feature, or open System Settings."

## How managers consume capabilities

`TextInsertionManager` does not call `CGEvent.post`. It asks `AccessibilityCapability.postKeyEvent(...)`. If the capability throws, the manager surfaces a typed error up to `RiverSession`, which logs and updates state.

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

`OnboardingView` does not know about specific capabilities. It iterates `[any Capability]` and renders a row per capability with name, status (from the publisher), and a `Grant` button that either triggers the auto-prompt (Microphone) or opens System Settings (Accessibility, Input Monitoring). The window opens whenever **any** capability's status is not `.granted`.

**Why:** any new permission added in the future just registers a new capability. Onboarding gets the new row for free. The "onboarding only fires on tap failure" failure mode is structurally impossible — the gating signal is "all capabilities granted," not "managers started successfully."

## Self-detection of TCC bundle misidentification

`AccessibilityCapability.postKeyEvent` can detect the silent-no-op failure mode (where TCC accepts the call but doesn't deliver the event because the bundle ID isn't what TCC expected). It does this by attempting a small synthesized round-trip and checking for the expected side effect. If the action silently no-ops, the capability transitions `status` to `.denied` with a diagnostic logged at `.warning`, even if the OS reported `.granted`.

This is the third anti-pattern (bespoke bundle assembly) gaining a structural detector: a misconfigured bundle now manifests as `AccessibilityCapability.status == .denied`, which immediately opens onboarding, which tells the user something is wrong.

## Capabilities and the threading invariant

`InputMonitoringCapability` owns the dedicated event-tap background thread (`com.river.eventtap`, QoS `.userInteractive`). It exposes the tap as a typed event stream that `HotkeyManager` consumes on the main actor (via `Task { @MainActor in ... }`). The threading rule belongs to the capability now, not to a free-floating manager. See [threading-invariant.md](threading-invariant.md).

## Related

- [permissions.md](permissions.md) — user-facing description of the three permissions
- [river-session.md](river-session.md) — the session that consumes the capability-backed managers
- [threading-invariant.md](threading-invariant.md) — the rule that `InputMonitoringCapability` enforces
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — the lying-check and silent-paste anti-patterns that capabilities make structurally impossible
