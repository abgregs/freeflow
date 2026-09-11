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
        // A *voiced* buffer — stopRecording now trims silence, so a zero buffer
        // would trim to empty (see AudioCaptureSilenceTrimTests).
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
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
        // Voiced buffer: stopRecording trims silence, so zeros would trim to empty.
        microphone.publishForTest(makeSineBuffer(milliseconds: 50, frequency: 440, amplitude: 0.5))

        let samples = try await stopTask.value
        #expect(samples.count > 700)  // ~50 ms at 16 kHz ≈ 800 samples (margin keeps all)
        #expect(samples.count < 900)
    }
}

@Suite("AudioCaptureManager discard")
struct AudioCaptureDiscardTests {
    // The cancel path (planning 0017): discardRecording drops captured buffers and
    // stops the engine WITHOUT converting or returning them — the counterpart to
    // stopRecording's convert-and-return.

    @MainActor
    @Test("discardRecording drops captured buffers so a later stop sees no audio")
    func discardDropsBuffers() async throws {
        // Capture a real (voiced) buffer, then discard. Re-arming a fresh recording
        // and stopping it with no new buffer must throw .noAudioCaptured — proof the
        // discarded buffers were dropped, not carried into the next recording.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        await manager.discardRecording()

        await manager.startRecording()  // fresh recording, no buffer published
        await #expect(throws: AudioCaptureError.self) {
            _ = try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("discardRecording is safe when nothing was captured")
    func discardWithNothingCaptured() async {
        // Cancel can arrive before any buffer landed (a stray key-brush). Discard
        // must not throw or wait — it simply tears down and drops nothing.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()
        await manager.discardRecording()  // no throw, no warmup wait
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

    @MainActor
    @Test("convert throws .conversionFailed when no converter can be built for the source format")
    func convertThrowsWhenConverterUnbuildable() throws {
        // The `.conversionFailed` guard: a zero-channel source format has no valid
        // conversion path to 16 kHz mono, so `AVAudioConverter(from:to:)` returns
        // nil. Buffers are non-empty (so the early empty-return doesn't mask this),
        // but decoding never starts. Without this branch a converter failure would
        // surface as a crash or a silent empty result instead of `.noAudioCaptured`'s
        // sibling error the session can report.
        let badFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 0, interleaved: false
        )!
        #expect(throws: AudioCaptureError.self) {
            _ = try AudioCaptureManager.convert([makeBuffer(milliseconds: 100)], from: badFormat)
        }
    }

    @MainActor
    @Test("convert preserves signal energy, not just length, for a non-silent input")
    func convertPreservesSignalEnergy() throws {
        // The length tests feed silent zero buffers, so a converter that emitted
        // zeros of the right length would pass them. Feed a real 440 Hz sine and
        // assert the 16 kHz output carries energy (RMS well above zero) — proof the
        // samples are actually resampled, not blanked. Energy/shape, not sample
        // equality: AVAudioConverter latency makes exact-match brittle.
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
        )!
        let samples = try AudioCaptureManager.convert(
            [makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5)], from: format
        )
        #expect(samples.count > 1500)   // same resampler-latency window as the silent case
        #expect(samples.count < 1700)
        let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.1)              // a 0.5-amplitude sine is ~0.35 RMS; zeros would be 0
    }
}

@Suite("AudioCaptureManager silence trim")
struct AudioCaptureSilenceTrimTests {
    // Whisper hallucinates text from silence — pasting words the user never spoke
    // is this app's worst failure. `trimSilence` drops below-threshold audio at
    // both ends of the 16 kHz buffer, keeping a margin so speech is never clipped.
    // Same synthetic-input pattern as the convert tests. See planning 0023.

    @MainActor
    @Test("all-silence input trims to empty")
    func allSilenceTrimsToEmpty() {
        // An accidental activation captures pure silence. It must trim to empty so
        // the session skips decode entirely — no hallucinated paste.
        let silence = [Float](repeating: 0, count: 16_000)  // 1 s of digital silence
        #expect(AudioCaptureManager.trimSilence(silence).isEmpty)
    }

    @MainActor
    @Test("empty input trims to empty")
    func emptyTrimsToEmpty() {
        #expect(AudioCaptureManager.trimSilence([]).isEmpty)
    }

    @MainActor
    @Test("silence-padded speech keeps the speech with a margin, dropping the padding")
    func paddedSpeechPreservesSpeech() {
        // 0.5 s silence, 0.5 s voiced, 0.5 s silence at 16 kHz. The leading/trailing
        // silence beyond the 100 ms margin must be dropped, but the speech and its
        // onset/offset margin must survive intact.
        let pad = [Float](repeating: 0, count: 8_000)
        let speech = sineSamples(count: 8_000, frequency: 440, amplitude: 0.5)
        let padded = pad + speech + pad

        let out = AudioCaptureManager.trimSilence(padded)

        #expect(out.count < padded.count)          // padding trimmed
        #expect(out.count >= speech.count)         // speech + margins survive
        #expect(out.count < padded.count - 8_000)  // most of one silent side is gone
        let rms = (out.reduce(Float(0)) { $0 + $1 * $1 } / Float(out.count)).squareRoot()
        #expect(rms > 0.1)                         // preserved speech carries energy
    }

    @MainActor
    @Test("speech-only input is returned untouched")
    func speechOnlyUntouched() {
        // No silence to trim: every window is voiced, so the whole buffer survives
        // (the margin clamps to the array bounds). Length is unchanged.
        let speech = sineSamples(count: 16_000, frequency: 440, amplitude: 0.5)
        #expect(AudioCaptureManager.trimSilence(speech).count == speech.count)
    }
}

// A 16 kHz mono Float32 sample array holding a pure sine — a synthetic "speech"
// signal with known energy for the trim tests (mirrors makeSineBuffer, but as a
// bare sample array since trimSilence operates on the converted buffer).
private func sineSamples(
    count: Int, frequency: Double, amplitude: Float, sampleRate: Double = 16_000
) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2.0 * .pi * frequency * Double($0) / sampleRate)) }
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

// Synthesize a non-silent 44.1 kHz mono Float32 buffer holding a pure sine, so a
// conversion test can assert the output carries real energy (not zeros of the
// right length). Amplitude and frequency are fixed by the caller for a known RMS.
@MainActor
private func makeSineBuffer(
    milliseconds: Int, frequency: Double, amplitude: Float, sampleRate: Double = 44_100
) -> AVAudioPCMBuffer {
    let buffer = makeBuffer(milliseconds: milliseconds, sampleRate: sampleRate)
    let frames = Int(buffer.frameLength)
    let channel = buffer.floatChannelData![0]
    for i in 0..<frames {
        channel[i] = amplitude * Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
    }
    return buffer
}
