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
    private var engine: AVAudioEngine?
    private(set) var inputFormat: AVAudioFormat?

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

    init() {
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
            Task { @MainActor in
                self.audioBufferSubject.send(copy)
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
        audioLogger.info("AVAudioEngine stopped")
    }

    // internal for testability — pushes a synthetic buffer into the stream
    // synchronously on the main actor, bypassing the engine (which requires a
    // Microphone grant on the running process).
    func publishForTest(_ buffer: AVAudioPCMBuffer) {
        audioBufferSubject.send(buffer)
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
