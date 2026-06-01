import Combine
import CoreGraphics
import Foundation
import Testing
@testable import FreeFlow

@Suite("HotkeyManager Hold mode")
struct HotkeyManagerHoldTests {
    // The manager interprets the raw TapEvent stream into semantic activate /
    // deactivate. Tests drive it via `handle(_:)` (and via the Combine chain
    // when verifying wiring) — never through a real CGEventTap, which would
    // require an Input Monitoring grant for the test process.

    @MainActor
    @Test("watched key: alternating flagsChanged events fire activate then deactivate")
    func watchedKeyTogglesAndFires() {
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(inputMonitoring: cap, initialKeyCode: 62)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(activates == 1)
        #expect(deactivates == 0)

        manager.handle(.flagsChanged(keyCode: 62, flags: []))
        #expect(activates == 1)
        #expect(deactivates == 1)

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(activates == 2)
    }

    @MainActor
    @Test("non-watched keycode is ignored — no callbacks, no latch change")
    func nonWatchedKeyIgnored() {
        // Left/right modifier variants share a flag mask; disambiguation is by
        // keycode. A Left Control event must NOT trigger when Right Control is
        // the watched key.
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(inputMonitoring: cap, initialKeyCode: 62)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 59, flags: .maskControl))  // Left Control
        manager.handle(.flagsChanged(keyCode: 59, flags: []))
        #expect(activates == 0)
        #expect(deactivates == 0)
    }

    @MainActor
    @Test(".tapDisabled is a no-op for the manager (capability self-heals)")
    func tapDisabledIsNoOp() {
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(inputMonitoring: cap, initialKeyCode: 62)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.tapDisabled)
        #expect(activates == 0)
        #expect(deactivates == 0)
    }

    @MainActor
    @Test("setActivationKeyCode resets the press latch")
    func setActivationKeyCodeResetsLatch() {
        // If the user reconfigures mid-press, the stale "key still down" state
        // must not survive — otherwise the next event for the new key fires a
        // phantom deactivate (anti-pattern #7 in spirit: don't leak cycle state
        // across reconfiguration).
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(inputMonitoring: cap, initialKeyCode: 62)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // press old key
        #expect(activates == 1)

        manager.setActivationKeyCode(59)  // switch to Left Control mid-press

        manager.handle(.flagsChanged(keyCode: 59, flags: .maskControl))  // new press
        #expect(activates == 2)
        #expect(deactivates == 0)  // latch was reset; this is a press, not a release

        manager.handle(.flagsChanged(keyCode: 59, flags: []))             // new release
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("bindEventStream wires capability events to handle (via Combine)")
    func bindEventStreamWiresChain() {
        // End-to-end through the publisher chain without a real tap: the
        // capability's `publishForTest` sends synchronously on the main actor,
        // the manager's sink receives synchronously, and the activate fires.
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(inputMonitoring: cap, initialKeyCode: 62)
        manager.bindEventStream()
        var activates = 0
        manager.onActivate = { activates += 1 }

        cap.publishForTest(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(activates == 1)
    }
}
