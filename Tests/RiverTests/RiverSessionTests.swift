import Foundation
import Testing
@testable import River

@Suite("RiverSession")
struct RiverSessionTests {
    @MainActor
    @Test("start leaves state idle and is idempotent")
    func startIsIdempotentNoOpCycle() async throws {
        let session = makeSession()
        #expect(session.currentState == .idle)
        try await session.start()
        #expect(session.currentState == .idle)
        try await session.start()
        #expect(session.currentState == .idle)
    }

    @MainActor
    @Test("stop is idempotent")
    func stopIsIdempotent() async throws {
        let session = makeSession()
        try await session.start()
        await session.stop()
        await session.stop()
        #expect(session.currentState == .idle)
    }

    @MainActor
    private func makeSession() -> RiverSession {
        let accessibility = AccessibilityCapability()
        let microphone = MicrophoneCapability()
        let inputMonitoring = InputMonitoringCapability()
        return RiverSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: HotkeyManager(inputMonitoring: inputMonitoring),
            audio: AudioCaptureManager(microphone: microphone),
            textInsertion: TextInsertionManager(accessibility: accessibility),
            transcription: TranscriptionService(),
            settings: SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        )
    }
}
