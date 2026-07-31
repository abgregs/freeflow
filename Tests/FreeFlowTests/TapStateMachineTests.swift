import Testing
@testable import FreeFlow

@Suite("TapStateMachine")
struct TapStateMachineTests {
    // The double-tap window is timing-sensitive, so the machine takes an injected
    // clock; tests advance a captured `TimeInterval` rather than sleep. Window is
    // 400 ms throughout.

    @MainActor
    @Test("single tap: tap starts, next tap stops, and it cycles")
    func singleTapCycle() {
        let machine = TapStateMachine(mode: .singleTap, windowMs: 400, now: { 0 })
        #expect(machine.handleTap() == .start)
        #expect(machine.handleTap() == .stop)
        #expect(machine.handleTap() == .start)
    }

    @MainActor
    @Test("double tap within the window starts")
    func doubleTapWithinWindowStarts() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(machine.handleTap() == .none)   // first tap → awaiting
        clock = 0.300                            // 300 ms later
        #expect(machine.handleTap() == .start)   // within 400 ms
    }

    @MainActor
    @Test("double tap outside the window does not start; it restarts detection")
    func doubleTapOutsideWindowRestarts() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(machine.handleTap() == .none)   // first tap @ 0
        clock = 1.0                              // 1000 ms later — too slow
        #expect(machine.handleTap() == .none)   // becomes the new first tap
        clock = 1.2                              // 200 ms after the new first tap
        #expect(machine.handleTap() == .start)   // now within the window
    }

    @MainActor
    @Test("double tap exactly at the window boundary starts")
    func doubleTapBoundaryStarts() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(machine.handleTap() == .none)
        clock = 0.400                            // exactly 400 ms — inclusive
        #expect(machine.handleTap() == .start)
    }

    @MainActor
    @Test("double tap stops on a single tap")
    func doubleTapStopsOnSingleTap() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        _ = machine.handleTap()                  // first tap
        clock = 0.100
        #expect(machine.handleTap() == .start)   // recording
        clock = 5.0                              // much later — a lone tap
        #expect(machine.handleTap() == .stop)    // a single tap stops
    }

    @MainActor
    @Test("setMode preserves an active recording but clears a pending double-tap")
    func setModePreservesRecording() {
        let recording = TapStateMachine(mode: .singleTap, windowMs: 400, now: { 0 })
        #expect(recording.handleTap() == .start)
        recording.setMode(.doubleTap)            // live mode change mid-recording
        #expect(recording.handleTap() == .stop)  // the recording is still stoppable

        var clock: Double = 0
        let awaiting = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(awaiting.handleTap() == .none)   // pending second tap
        awaiting.setMode(.singleTap)             // mode change clears the half-done detection
        #expect(awaiting.handleTap() == .start)  // a fresh single-tap start, not a stop
    }

    @MainActor
    @Test("hold mode is never interpreted here")
    func holdReturnsNone() {
        let machine = TapStateMachine(mode: .hold, windowMs: 400, now: { 0 })
        #expect(machine.handleTap() == .none)
    }

    @MainActor
    @Test("reset returns to idle without firing a spurious stop")
    func resetReturnsToIdle() {
        // reset drops any in-flight recording/detection back to the start state.
        // The next tap must behave like a fresh start (.start), not a stop of the
        // discarded recording — a stray .stop here would desync the session.
        let machine = TapStateMachine(mode: .singleTap, windowMs: 400, now: { 0 })
        #expect(machine.handleTap() == .start)   // now .recording
        machine.reset()
        #expect(machine.state == .idle)
        #expect(machine.handleTap() == .start)   // fresh start, not a stop
    }
}
