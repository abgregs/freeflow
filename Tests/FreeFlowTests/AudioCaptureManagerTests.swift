import AVFoundation
import Combine
import Foundation
import Testing
@testable import FreeFlow

@Suite("AudioCaptureManager capture cycle")
struct AudioCaptureCycleTests {
    @MainActor
    @Test("stopRecording returns 16 kHz samples when a buffer was published")
    func stopRecordingReturnsSamples() async throws {
        // Happy path: a single 100 ms buffer at 44.1 kHz → ~1600 samples at 16 kHz.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()
        microphone.publishForTest(makeBuffer(milliseconds: 100))
        let samples = try await manager.stopRecording()
        #expect(samples.count > 1500)
        #expect(samples.count < 1700)
    }

    @MainActor
    @Test("stopRecording throws .noAudioCaptured when no buffer arrives within the warmup window")
    func stopRecordingThrowsWhenSilent() async {
        // Fail-loud rule (core-feature.md item 2): zero-length recording must
        // surface, never silently succeed. Test takes ~300 ms (the warmup wait).
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()
        await #expect(throws: AudioCaptureError.self) {
            _ = try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("a buffer that arrives late (within warmup) still produces samples")
    func lateBufferStillCaptures() async throws {
        // Engine-warmup race: a short tap that releases right when the engine
        // first produces audio. The 300 ms wait inside stopRecording is what
        // saves this case. We model it by running stopRecording in a child Task
        // and publishing the buffer from the test's own timeline — that puts
        // the buffer arrival deterministically inside the wait window without
        // two peer Tasks racing for the MainActor scheduler.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()

        let stopTask = Task { @MainActor in
            try await manager.stopRecording()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        microphone.publishForTest(makeBuffer(milliseconds: 50))

        let samples = try await stopTask.value
        #expect(samples.count > 700)  // ~50 ms at 16 kHz ≈ 800 samples
        #expect(samples.count < 900)
    }
}

@Suite("AudioCaptureManager sample-rate conversion")
struct AudioCaptureConvertTests {
    @MainActor
    @Test("convert([]) returns an empty sample array")
    func convertEmpty() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
        )!
        let samples = try AudioCaptureManager.convert([], from: format)
        #expect(samples.isEmpty)
    }

    @MainActor
    @Test("convert downsamples 44.1 kHz mono Float32 to 16 kHz at the expected length")
    func convertDownsamples() throws {
        // 4410 frames @ 44.1 kHz = 100 ms → ~1600 frames @ 16 kHz. AVAudioConverter
        // has resampler latency, so we allow some tolerance instead of an exact match.
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
        )!
        let samples = try AudioCaptureManager.convert([makeBuffer(milliseconds: 100)], from: format)
        #expect(samples.count > 1500)
        #expect(samples.count < 1700)
    }
}

// Synthesize a silent 44.1 kHz mono Float32 buffer of the requested duration.
// Zeros are sufficient for length/conversion tests; M6 will exercise real audio.
@MainActor
private func makeBuffer(milliseconds: Int, sampleRate: Double = 44_100) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
    )!
    let frames = AVAudioFrameCount(Double(milliseconds) * sampleRate / 1000.0)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    return buffer
}
