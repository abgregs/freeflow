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

@Suite("HotkeyManager tap modes")
struct HotkeyManagerTapTests {
    // Tap modes act only on the completing (key-up) edge of a tap and route
    // start/stop through the embedded TapStateMachine. Double-tap timing itself is
    // covered in TapStateMachineTests; here two *immediate* taps are well within
    // the 400 ms window, so they always pair under the real clock.

    @MainActor
    @Test("single tap: a completed tap starts, the next stops")
    func singleTapToggles() {
        let manager = makeManager(mode: .singleTap)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // key-down
        #expect(activates == 0)  // a press alone does nothing in tap modes
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // key-up → tap → start
        #expect(activates == 1)

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // tap → stop
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("holding the key in a tap mode is a single tap (fires on release only)")
    func holdIsOneTap() {
        let manager = makeManager(mode: .singleTap)
        var activates = 0
        manager.onActivate = { activates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // press and "hold"
        #expect(activates == 0)
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // release completes the one tap
        #expect(activates == 1)
    }

    @MainActor
    @Test("double tap: two quick taps start, one tap stops")
    func doubleTapStartsAndStops() {
        let manager = makeManager(mode: .doubleTap)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        tap(manager)
        #expect(activates == 0)  // first tap: awaiting the second
        tap(manager)
        #expect(activates == 1)  // second tap within the window → start

        tap(manager)
        #expect(deactivates == 1)  // a single tap stops
    }

    @MainActor
    @Test("a live key change preserves the recording: the new key stops it, the old key is ignored")
    func liveKeyChangePreservesRecording() {
        // This is the load-bearing behavior for live-apply (free-flow-session.md):
        // switching the key mid-recording is a refilter, the tap machine keeps its
        // .recording state, so the new key stops the in-flight recording while the
        // old key falls silent.
        let manager = makeManager(mode: .singleTap)
        var deactivates = 0
        manager.onActivate = {}
        manager.onDeactivate = { deactivates += 1 }

        tap(manager)                          // start recording on key 62
        manager.setActivationKeyCode(59)      // live key change to Left Control

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // old key…
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // …now ignored
        #expect(deactivates == 0)

        manager.handle(.flagsChanged(keyCode: 59, flags: .maskControl))  // new key…
        manager.handle(.flagsChanged(keyCode: 59, flags: []))            // …stops the recording
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("switching from Hold to a tap mode resets the press latch")
    func modeSwitchResetsLatch() {
        let manager = makeManager(mode: .hold)
        var activates = 0
        manager.onActivate = { activates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // Hold: down → activate
        #expect(activates == 1)
        manager.setActivationMode(.singleTap)  // switch mid-press; latch must reset

        tap(manager)  // a clean tap on the new mode starts a recording
        #expect(activates == 2)
    }

    @MainActor
    private func makeManager(mode: ActivationMode) -> HotkeyManager {
        HotkeyManager(inputMonitoring: InputMonitoringCapability(), initialKeyCode: 62, initialMode: mode)
    }

    @MainActor
    private func tap(_ manager: HotkeyManager, keyCode: Int64 = 62) {
        manager.handle(.flagsChanged(keyCode: keyCode, flags: .maskControl))
        manager.handle(.flagsChanged(keyCode: keyCode, flags: []))
    }
}
