import AppKit
import AVFoundation
import Combine
import Foundation
import os

@MainActor
final class MicrophoneCapability: Capability {
    let displayName = "Microphone"

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "permissions")
    private let audioLogger = Logger(subsystem: Constants.loggingSubsystem, category: "audio")
    private let subject: CurrentValueSubject<CapabilityStatus, Never>

    // fileprivate so the audio tap callback (in this file) can deliver into it.
    fileprivate let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    // Live input level (0...1), throttled — the recording HUD's level meter reads
    // this so a silent mic is visible *during* capture (planning 0020).
    private let levelSubject = PassthroughSubject<Float, Never>()
    private var engine: AVAudioEngine?
    private(set) var inputFormat: AVAudioFormat?

    // Throttle state for the level publisher: `nil` until the first sample so the
    // first buffer always emits. Injectable clock so the ~14 Hz throttle is tested
    // deterministically (planning 0020 acceptance criterion 3).
    private let now: () -> TimeInterval
    private var lastLevelEmit: TimeInterval?

    // internal for testability — when true, `startEngine` is a no-op. The test
    // runner often has Microphone permission, so without this `AVAudioEngine.start`
    // succeeds and real silence (or noise) leaks into tests via the tap callback,
    // racing with synthetic buffers from `publishForTest`. The M4 pattern got
    // this for free because `tapCreate` returns nil without Input Monitoring;
    // mic capture has no equivalent natural skip.
    var skipEngineForTesting = false

    var status: AnyPublisher<CapabilityStatus, Never> { subject.eraseToAnyPublisher() }
    var currentStatus: CapabilityStatus { subject.value }

    /// Buffers from the audio input tap. Subscribers receive on the main actor
    /// (the tap callback hops via `Task { @MainActor in ... }` per the threading
    /// invariant). Buffers are deep-copied — the tap's buffer is reused after
    /// the callback returns.
    var audioBuffers: AnyPublisher<AVAudioPCMBuffer, Never> { audioBufferSubject.eraseToAnyPublisher() }

    /// Throttled input level (0...1) during capture. Emits on the main actor (the
    /// tap callback hops via `Task { @MainActor in ... }`, same discipline as the
    /// buffer stream and the event tap). `AppState.bind(microphone:)` subscribes;
    /// the recording HUD renders it (planning 0020).
    var inputLevels: AnyPublisher<Float, Never> { levelSubject.eraseToAnyPublisher() }

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        subject = CurrentValueSubject(Self.readStatus())
    }

    func recheck() async {
        updateStatus(Self.readStatus())
    }

    /// Microphone is the one permission macOS lets us auto-prompt for. After the
    /// user answers the system dialog, re-read the authoritative status.
    func requestGrant() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        logger.info("Microphone access request resolved: granted=\(granted, privacy: .public)")
        await recheck()
    }

    func openSystemSettings() {
        SystemSettingsPane.microphone.open()
    }

    /// Starts the `AVAudioEngine` and installs an input tap that publishes
    /// (deep-copied) buffers to `audioBuffers`. Idempotent. If the engine fails
    /// to start (typically because Microphone isn't granted for the running
    /// process), logs a warning and returns — the capability's `status` already
    /// reports `.denied`/`.unknown` to onboarding upstream. Mirrors the
    /// fail-quiet pattern in `InputMonitoringCapability.startTap`.
    func startEngine() async {
        guard engine == nil else { return }
        if skipEngineForTesting { return }
        let engine = AVAudioEngine()
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            audioLogger.warning("Input node returned a zero-sampleRate format — no microphone available.")
            return
        }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let copy = Self.copy(buffer)
            // RMS is computed here on the audio thread (pure, no `self` access), so
            // only the throttled emission crosses to the main actor.
            let rms = Self.rms(of: buffer)
            Task { @MainActor in
                self.audioBufferSubject.send(copy)
                self.emitLevel(rms: rms)
            }
        }
        do {
            try engine.start()
            self.engine = engine
            self.inputFormat = format
            audioLogger.info("AVAudioEngine started; input format \(format.sampleRate, privacy: .public) Hz \(format.channelCount, privacy: .public) ch")
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            audioLogger.warning("AVAudioEngine.start failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
        }
    }

    /// Removes the input tap and stops the engine. Idempotent.
    func stopEngine() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.inputFormat = nil
        // Reset the throttle so the next recording's first buffer emits a level
        // immediately rather than being gated by the previous recording's timestamp.
        lastLevelEmit = nil
        audioLogger.info("AVAudioEngine stopped")
    }

    // internal for testability — pushes a synthetic buffer into the stream
    // synchronously on the main actor, bypassing the engine (which requires a
    // Microphone grant on the running process).
    func publishForTest(_ buffer: AVAudioPCMBuffer) {
        audioBufferSubject.send(buffer)
    }

    // internal for testability — the throttled level emission, split from the tap
    // callback so the ~14 Hz throttle is tested with an injected clock without a
    // real engine (planning 0020 AC3). Emits the normalized level on the main actor;
    // buffers arriving inside `levelMeterPublishInterval` of the last emission are
    // dropped (the meter doesn't need every buffer).
    func emitLevel(rms: Float) {
        let t = now()
        if let last = lastLevelEmit, t - last < Constants.levelMeterPublishInterval { return }
        lastLevelEmit = t
        levelSubject.send(Self.normalizedLevel(rms: rms))
    }

    // internal for testability — RMS of a buffer's first channel. Pure and
    // audio-thread-safe (no `self`), so the tap callback computes it before hopping
    // to the main actor, and tests exercise it on synthetic loud/quiet/silent
    // buffers (planning 0020 AC2).
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        let samples = channelData[0]
        var sumSquares: Float = 0
        for i in 0..<count { sumSquares += samples[i] * samples[i] }
        return (sumSquares / Float(count)).squareRoot()
    }

    // internal for testability — maps a linear RMS to a 0...1 meter level. A speech
    // peak near `levelMeterReferenceRMS` lights the full meter; silence is 0; quiet
    // speech sits proportionally low. Clamped so a loud transient can't exceed 1.
    static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        return min(1, rms / Constants.levelMeterReferenceRMS)
    }

    private func updateStatus(_ next: CapabilityStatus) {
        guard subject.value != next else { return }
        logger.info("Microphone status -> \(String(describing: next), privacy: .public)")
        subject.send(next)
    }

    private static func readStatus() -> CapabilityStatus {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    // `.notDetermined` honestly maps to `.unknown`: we have not asked yet, so we
    // cannot claim either grant or denial. Lowering it to `.denied` would mislabel
    // a promptable state as a hard refusal. Internal for deterministic testing.
    static func map(_ status: AVAuthorizationStatus) -> CapabilityStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    // The tap callback's buffer is reused after the closure returns; appending
    // it directly would later read freed memory. Deep-copy now while we're
    // still on the audio thread.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
        if let srcData = buffer.floatChannelData, let dstData = copy.floatChannelData {
            for channel in 0..<channels {
                memcpy(dstData[channel], srcData[channel], bytes)
            }
        }
        return copy
    }
}
