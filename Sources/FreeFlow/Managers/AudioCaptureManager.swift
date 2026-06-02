import AVFoundation
import Combine
import Foundation
import os

enum AudioCaptureError: Error, LocalizedError {
    /// `stopRecording` returned without ever seeing a buffer (engine never
    /// warmed up or the tap silently delivered none). Surfaced loudly per
    /// `requirements/core-feature.md` item 2 — short taps must not silently
    /// produce a zero-length recording.
    case noAudioCaptured
    /// `AVAudioConverter` initialization or `convert` returned an error.
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .noAudioCaptured:
            return "No audio was captured (engine may have failed to start)."
        case .conversionFailed:
            return "Could not convert recorded audio to 16 kHz mono."
        }
    }
}

@MainActor
final class AudioCaptureManager {
    private let microphone: MicrophoneCapability
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "audio")

    private var buffers: [AVAudioPCMBuffer] = []
    private var cancellables = Set<AnyCancellable>()

    /// Upper bound on the engine-warmup wait inside `stopRecording`. `AVAudioEngine`
    /// produces its first tap-callback buffer ~60-100 ms after `start()`; a short
    /// tap that releases inside that window would otherwise drop the utterance.
    /// See `architecture/free-flow-pipeline.md` "Engine warmup".
    static let warmupWaitSeconds: Double = 0.3

    init(microphone: MicrophoneCapability) {
        self.microphone = microphone
    }

    /// Subscribes to the capability's buffer stream and starts the engine.
    /// Idempotent on the subscription side; the capability's `startEngine` is
    /// itself idempotent. Note: this never throws — the capability fails quietly
    /// (logged warning) if the engine can't start. `stopRecording` is the
    /// fail-loud surface (throws `.noAudioCaptured` if no buffers arrived).
    func startRecording() async {
        guard cancellables.isEmpty else { return }
        buffers.removeAll(keepingCapacity: true)
        microphone.audioBuffers
            .sink { [weak self] buffer in self?.buffers.append(buffer) }
            .store(in: &cancellables)
        await microphone.startEngine()
    }

    /// Waits up to `warmupWaitSeconds` for the first buffer (so short taps still
    /// produce audio), then tears down the subscription, stops the engine, and
    /// converts the accumulated buffers to 16 kHz mono Float32. Throws
    /// `.noAudioCaptured` if the wait expired with no buffers — the caller
    /// (FreeFlowSession) surfaces this rather than letting a zero-length
    /// recording silently succeed.
    func stopRecording() async throws -> [Float] {
        let deadline = Date().addingTimeInterval(Self.warmupWaitSeconds)
        while buffers.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        cancellables.removeAll()
        microphone.stopEngine()

        guard let firstBuffer = buffers.first else {
            logger.warning("stopRecording: no audio buffers arrived within \(Self.warmupWaitSeconds, privacy: .public)s")
            throw AudioCaptureError.noAudioCaptured
        }

        let sourceFormat = firstBuffer.format
        let collected = buffers
        buffers.removeAll(keepingCapacity: true)

        let samples = try Self.convert(collected, from: sourceFormat)
        logger.info("Captured \(samples.count, privacy: .public) samples (16 kHz mono) from \(collected.count, privacy: .public) buffers @ \(sourceFormat.sampleRate, privacy: .public) Hz")
        return samples
    }

    // internal for testability — pure conversion from N hardware-format buffers
    // to a single 16 kHz mono Float32 sample array. Done once at stop time
    // rather than inside the tap callback (free-flow-pipeline.md step 3).
    static func convert(
        _ buffers: [AVAudioPCMBuffer],
        from sourceFormat: AVAudioFormat,
        toSampleRate: Double = 16_000
    ) throws -> [Float] {
        guard !buffers.isEmpty else { return [] }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: toSampleRate,
            channels: 1,
            interleaved: false
        ) else { throw AudioCaptureError.conversionFailed }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioCaptureError.conversionFailed
        }

        let inputFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        // Conservative capacity: input × rate ratio + headroom for resampler latency.
        let outputCapacity = AVAudioFrameCount(
            ceil(Double(inputFrames) * (toSampleRate / sourceFormat.sampleRate)) + 1024
        )

        var feedIndex = 0
        let inputBlock: AVAudioConverterInputBlock = { _, statusOut in
            guard feedIndex < buffers.count else {
                statusOut.pointee = .endOfStream
                return nil
            }
            statusOut.pointee = .haveData
            let buffer = buffers[feedIndex]
            feedIndex += 1
            return buffer
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int(outputCapacity))

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                throw AudioCaptureError.conversionFailed
            }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if error != nil { throw AudioCaptureError.conversionFailed }
            let frames = Int(outputBuffer.frameLength)
            if frames > 0, let channelData = outputBuffer.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
            }
            if status == .endOfStream || status == .inputRanDry || status == .error || frames == 0 {
                break
            }
        }

        return samples
    }
}
