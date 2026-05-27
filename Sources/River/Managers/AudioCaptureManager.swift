import Foundation

@MainActor
final class AudioCaptureManager {
    private let microphone: MicrophoneCapability

    init(microphone: MicrophoneCapability) {
        self.microphone = microphone
    }
}
