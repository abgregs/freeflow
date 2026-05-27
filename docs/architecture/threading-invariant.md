# Architecture: Event-Tap Threading Invariant

The CGEventTap that detects the activation key runs its `CFRunLoop` on a **dedicated background thread named `com.river.eventtap` with QoS `.userInteractive`**. This is load-bearing.

The invariant is owned by [`InputMonitoringCapability`](capabilities.md). The capability is the only code that calls `CGEvent.tapCreate`, manages the tap lifecycle, or touches the background thread. `HotkeyManager` and `RiverSession` consume the capability's typed event stream; they never see the CFRunLoop or the thread directly.

## The rule

- The tap source must be added to `CFRunLoopGetCurrent()` from inside a `Thread` closure — never to `CFRunLoopGetMain()` or `RunLoop.main`.
- The thread is created with `qualityOfService = .userInteractive` and `name = "com.river.eventtap"`.
- Events from the tap are delivered to consumers on the main actor (via `Task { @MainActor in ... }`) before they touch shared state.

## Why

SwiftUI's main run loop can starve a tap source of events when the app is launched in certain ways (notably via `open` versus a Finder double-click). Symptom: the menu bar icon appears, the app says it's ready, the tap was successfully created — but key events never fire the callback. Silent and hard to diagnose.

Running the tap's CFRunLoop on its own background thread isolates it from anything competing for the main loop's attention. The QoS hint ensures macOS treats it as latency-critical, not background work.

## What you must not do

- Do **not** add the tap source to the main run loop, even temporarily during testing.
- Do **not** use `DispatchQueue.main.sync` to deliver tap events; deadlocks under SwiftUI scenes.
- Do **not** call `CGEvent.tapCreate` from anywhere other than `InputMonitoringCapability`. This is the seam that enforces the threading rule; bypassing it puts the burden on the new caller to remember the rule.
- Do **not** make `InputMonitoringCapability`'s event-decoding helpers `private`. Tests need internal access — they cannot exercise a real CGEventTap (no Accessibility / Input Monitoring grant in CI), so they synthesize `CGEvent`s and feed them directly. See [../conventions/tests.md](../conventions/tests.md).

## Self-healing the tap

macOS will disable a tap that blocks too long, sending the callback one final event with `type == .tapDisabledByTimeout` or `.tapDisabledByUserInput`. `InputMonitoringCapability` responds by calling `CGEvent.tapEnable(tap: tap, enable: true)` and returning. This is normal; do not treat it as an error in user-facing UI.

The same callback type also fires when the capability calls `CGEvent.tapEnable(... enable: false)` during teardown. Distinguish "we disabled it on purpose during stop" from "the system disabled it spontaneously" only by context, not by the type field — they're identical.

## Reconfiguration

When `RiverSession` triggers a reconfiguration (in response to a settings change), `HotkeyManager` asks `InputMonitoringCapability` to stop the current tap and start a new one with the new keycode of interest. The capability always:

1. Calls `CGEvent.tapEnable(... false)` on the current tap.
2. Calls `CFRunLoopStop` on the current background run loop.
3. Joins the thread.
4. Spawns a fresh `Thread` with the same name and QoS for the new tap.

There is no path that runs the new tap on the main loop, because there is no other place in the codebase that calls `CGEvent.tapCreate`.

## Related

- [capabilities.md](capabilities.md) — `InputMonitoringCapability` is the owner of this rule
- [river-pipeline.md](river-pipeline.md) — where the activation event fits in the broader cycle
- [permissions.md](permissions.md) — Input Monitoring is what makes tap creation possible at all
- [configuration.md](configuration.md) — live-apply path that triggers tap reconfiguration
