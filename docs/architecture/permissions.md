# Architecture: Permissions

Three permissions are required for Free Flow to work end-to-end. macOS surfaces them as three separate toggles in System Settings → Privacy & Security and treats them independently. Conflating them — or falling back from one to another — silently breaks the app.

This doc covers what each permission means to the user and the rules around requesting them. The mechanics of checking and using each permission are owned by the corresponding [Capability](capabilities.md).

## What each permission enables

| Permission | Capability | What it enables | How macOS prompts | Failure mode if missing |
|---|---|---|---|---|
| **Microphone** | `MicrophoneCapability` | Audio capture (`AVAudioEngine.start()`) | Auto-prompts when `AVCaptureDevice.requestAccess` is called | Capability refuses; cycle aborts with a typed error |
| **Input Monitoring** | `InputMonitoringCapability` | Creating the `CGEventTap` | Status via `IOHIDCheckAccess` (no prompt); first `CGEvent.tapCreate` may prompt | Capability refuses; activation key does nothing |
| **Accessibility** | `AccessibilityCapability` | Posting synthetic key events (`CGEvent.post`) | Programmatically requestable *once* via `AXIsProcessTrustedWithOptions`, then user-driven only | Capability refuses; recording works, but `insertText` throws and the cycle ends with a visible error |

## The Accessibility trap

Two pitfalls specifically around Accessibility — both of which the architecture neutralizes:

1. **`AXIsProcessTrustedWithOptions(... prompt: true)` fires its prompt at most once per app per machine.** If the user dismisses it, the app cannot re-prompt programmatically — and for self-signed dev builds the cdhash changes every build, so the one-shot prompt is unreliable anyway. M2 therefore skips it: the `Grant` button calls `AccessibilityCapability.openSystemSettings()`, which deep-links to the right pane, and onboarding directs the user to add the app via **+** with explicit instructions. Status itself is read with the non-prompting `AXIsProcessTrusted()`.

2. **Permission detection cannot lie.** Capabilities expose `CapabilityStatus` of `.granted` / `.denied` / `.unknown`. There is no fallback from one permission to another. The `.unknown` case exists explicitly for dev builds where TCC reporting is unreliable; it surfaces as an inline note in the UI, never as a green checkmark. See [capabilities.md](capabilities.md).

## How M2 detects status

Status is read with non-prompting APIs and never inferred from a different permission: Microphone via `AVCaptureDevice.authorizationStatus`, Accessibility via `AXIsProcessTrusted()`, Input Monitoring via `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` (a true granted/denied/unknown tri-state). Input Monitoring is **not** detected by creating a probe `CGEventTap` — that would breach the [threading invariant](threading-invariant.md). See [capabilities.md](capabilities.md#status-detection) for the full mapping table.

## Onboarding rules

- On every launch, every capability's `status` is checked.
- `OnboardingView` opens whenever **any** capability's status is not `.granted`. Not only on hotkey-tap failure. **Why:** even if one capability succeeds (Input Monitoring), the app is non-functional if another (Accessibility) does not. Onboarding's job is to prevent the user from ever reaching a working-but-broken state.
- Onboarding iterates `[any Capability]` and renders a row per capability. For Accessibility specifically, the row includes the explicit text: "Open System Settings → Privacy & Security → Accessibility, click +, navigate to `/Applications/FreeFlow.app`, and toggle it on. Then quit and relaunch Free Flow."
- A `Refresh permission status` button calls `recheck()` on each capability without quitting.
- A `Skip / I've already granted permissions` button exists as an escape hatch for unsigned dev builds, and is **compiled out of notarized release builds** (`FREEFLOW_RELEASE` flag — see [../planning/0005_release-pipeline-security.md](../planning/0005_release-pipeline-security.md)). **Why:** during development, ad-hoc-signed binaries change cdhash on every build and TCC may not reliably reflect granted state; a notarized build has a stable cdhash, so detection is reliable and the escape hatch isn't needed. Skip bypasses the onboarding gate but does not silence individual capability checks downstream — if a capability refuses an action at runtime, the failure still surfaces.

## Bundle-ID stability is part of the permission story

TCC keys grants by bundle identifier and code signature. If the bundle ID changes (e.g., from missing `Info.plist` to a present one), macOS treats the new bundle as a different app — and the old grants do not transfer. The user sees two entries for "Free Flow" and must clean up.

`AccessibilityCapability` includes a silent-no-op detector for the bundle-misidentification failure mode: it attempts a small synthesized round-trip on `recheck()` and on first use, and reports `.denied` if the OS accepts the call without delivering it. This is the symptom of a malformed bundle and the cue to fix it (or to clear stale TCC entries).

Stable bundle ID + stable signing identity prevents the churn. See [distribution.md](distribution.md).

## Related

- [capabilities.md](capabilities.md) — the per-permission modules that implement these rules
- [overview.md](overview.md) — where capabilities sit in the process model
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — the "lying permission check" and "onboarding only on hard failure" patterns the capability layer makes impossible
- [../requirements/core-feature.md](../requirements/core-feature.md) — the user-facing onboarding requirements
