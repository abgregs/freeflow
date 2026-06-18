import Combine
import CoreGraphics
import Foundation
import IOKit.hid
import os

/// Decoded event from the system-wide `CGEventTap`. `HotkeyManager` interprets
/// these against the configured activation key/mode; the capability emits raw
/// signals and stays ignorant of "activation" semantics.
enum TapEvent: Equatable, Sendable {
    case flagsChanged(keyCode: Int64, flags: CGEventFlags)
    case tapDisabled
}

@MainActor
final class InputMonitoringCapability: Capability {
    let displayName = "Input Monitoring"
    let setupInstructions: String? =
        "Open System Settings → Privacy & Security → Input Monitoring, click +, add /Applications/FreeFlow.app, and toggle it on. Then click Refresh permission status below — if it still shows Not granted, quit and relaunch Free Flow."

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "permissions")
    private let tapLogger = Logger(subsystem: Constants.loggingSubsystem, category: "hotkey")
    private let subject: CurrentValueSubject<CapabilityStatus, Never>

    // fileprivate so the C tap callback (in this file) can deliver into them.
    fileprivate let eventSubject = PassthroughSubject<TapEvent, Never>()
    fileprivate var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    /// Raw decoded events from the tap. Subscribers receive on the main actor
    /// (the C callback hops via `Task { @MainActor in ... }` per the threading
    /// invariant).
    var events: AnyPublisher<TapEvent, Never> { eventSubject.eraseToAnyPublisher() }

    init() {
        subject = CurrentValueSubject(Self.readStatus())
    }

    func recheck() async {
        update(Self.readStatus())
    }

    func openSystemSettings() {
        SystemSettingsPane.inputMonitoring.open()
    }

    /// Starts the system-wide CGEventTap on a dedicated `com.freeflow.eventtap`
    /// background thread (QoS `.userInteractive`). Idempotent. If `tapCreate`
    /// fails (typically because Input Monitoring isn't granted for the running
    /// process), logs a warning and returns — the capability's own `status`
    /// already reports `.denied`/`.unknown` to onboarding, so re-surfacing the
    /// failure here would be redundant. The hotkey simply produces no events
    /// until the user grants Input Monitoring and relaunches.
    func startTap() async {
        guard tapThread == nil else { return }
        let tapLogger = self.tapLogger
        let started: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var resumed = false
            let resume: (Bool) -> Void = { result in
                if !resumed { resumed = true; cont.resume(returning: result) }
            }
            let thread = Thread { [weak self] in
                guard let self else { resume(false); return }
                let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
                let userInfo = Unmanaged.passUnretained(self).toOpaque()
                guard let tap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    // Listen-only (least privilege): the callback only observes
                    // `.flagsChanged` and returns events unmodified, so it never
                    // needs to modify or consume input. `.listenOnly` makes that
                    // structurally impossible — the return value is ignored, and
                    // a stalled callback can't delay system-wide event delivery.
                    // See planning/0006_runtime-security-hardening.md.
                    options: .listenOnly,
                    eventsOfInterest: mask,
                    callback: handleTapCallback,
                    userInfo: userInfo
                ) else {
                    tapLogger.warning("CGEvent.tapCreate returned nil — hotkey will not fire until Input Monitoring is granted and the app relaunched.")
                    resume(false)
                    return
                }
                guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                    tapLogger.warning("CFMachPortCreateRunLoopSource returned nil")
                    resume(false)
                    return
                }
                let runLoop = CFRunLoopGetCurrent()
                CFRunLoopAddSource(runLoop, source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                Task { @MainActor in
                    self.tap = tap
                    self.tapRunLoop = runLoop
                }
                resume(true)
                CFRunLoopRun()  // blocks the thread until CFRunLoopStop
            }
            thread.qualityOfService = .userInteractive
            thread.name = "com.freeflow.eventtap"
            self.tapThread = thread
            thread.start()
        }
        if !started {
            tapThread = nil
            return
        }
        tapLogger.info("CGEventTap started on com.freeflow.eventtap")
    }

    /// Stops the tap and joins the dedicated thread. Idempotent.
    func stopTap() async {
        guard let tap, let tapRunLoop, let tapThread else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopStop(tapRunLoop)
        while !tapThread.isFinished {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        self.tap = nil
        self.tapRunLoop = nil
        self.tapThread = nil
        tapLogger.info("CGEventTap stopped")
    }

    // internal for testability — feeds a synthetic event into the stream
    // synchronously on the calling (main) actor, bypassing the tap-thread hop.
    func publishForTest(_ event: TapEvent) {
        eventSubject.send(event)
    }

    // internal for testability — pure CGEvent → TapEvent decoder. `nonisolated`
    // so the C tap callback (on the dedicated background thread) can call it
    // without crossing an actor boundary.
    nonisolated static func decode(_ event: CGEvent) -> TapEvent? {
        switch event.type {
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            return .flagsChanged(keyCode: keyCode, flags: event.flags)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .tapDisabled
        default:
            return nil
        }
    }

    private func update(_ next: CapabilityStatus) {
        guard subject.value != next else { return }
        logger.info("Input Monitoring status -> \(String(describing: next), privacy: .public)")
        subject.send(next)
    }

    /// `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` is the documented,
    /// non-prompting status check for Input Monitoring. It returns a true
    /// tri-state that maps 1:1 onto `CapabilityStatus`, so there is no guessing.
    private static func readStatus() -> CapabilityStatus {
        map(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent))
    }

    /// `kIOHIDAccessTypeUnknown` (never determined for this code signature) stays
    /// `.unknown` rather than being lowered to `.granted` — see capabilities.md
    /// "no lying". Internal for deterministic testing (the OS call above can't be
    /// exercised in CI).
    static func map(_ access: IOHIDAccessType) -> CapabilityStatus {
        if access == kIOHIDAccessTypeGranted { return .granted }
        if access == kIOHIDAccessTypeDenied { return .denied }
        return .unknown
    }
}

// File-level C callback: captures nothing, recovers the capability via the
// `userInfo` pointer, and hops to the main actor before touching `eventSubject`
// (threading-invariant.md). Re-enables the tap on `.tapDisabled*` so a timeout
// or user-input disablement self-heals without a manager round trip.
private func handleTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    if let decoded = InputMonitoringCapability.decode(event) {
        let ptrInt = UInt(bitPattern: userInfo)
        Task { @MainActor in
            guard let ptr = UnsafeMutableRawPointer(bitPattern: ptrInt) else { return }
            let capability = Unmanaged<InputMonitoringCapability>.fromOpaque(ptr).takeUnretainedValue()
            if case .tapDisabled = decoded, let tap = capability.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            capability.eventSubject.send(decoded)
        }
    }
    return Unmanaged.passUnretained(event)
}
