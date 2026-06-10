import AppKit
import Foundation
import Testing
@testable import FreeFlow

@Suite("TextInsertionManager", .serialized)
struct TextInsertionManagerTests {
    // These tests mutate `NSPasteboard.general` — the real system pasteboard,
    // a shared mutable resource across the suite. `.serialized` forces sequential
    // execution; without it, swift-testing's default parallelism lets a sleeping
    // test (250 ms restore gap) write the pasteboard between another test's
    // setString and the next savePasteboard, producing a non-deterministic flake.
    // Each test snapshots on entry and restores in defer — the price of testing
    // the manager without extracting a pasteboard abstraction (ADR 0001).

    @MainActor
    @Test("savePasteboard round-trips multiple types per item")
    func savePasteboardRoundTripsTypes() {
        // The save/restore surface must preserve non-string content. Locks in
        // requirement core-feature.md item 4: "The user's original clipboard is
        // restored after the paste lands" — for *whatever* content was there,
        // not just strings.
        let manager = TextInsertionManager(accessibility: AccessibilityCapability())
        let preTestSnapshot = manager.savePasteboard()
        defer { manager.restorePasteboard(preTestSnapshot) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(Data("hello".utf8), forType: .string)
        item.setData(Data("<b>hi</b>".utf8), forType: .html)
        pasteboard.writeObjects([item])

        let snapshot = manager.savePasteboard()

        pasteboard.clearContents()
        pasteboard.setString("clobbered", forType: .string)

        manager.restorePasteboard(snapshot)
        #expect(pasteboard.string(forType: .string) == "hello")
        #expect(pasteboard.data(forType: .html) == Data("<b>hi</b>".utf8))
    }

    @MainActor
    @Test("insertText writes text, posts ⌘V via capability, restores pasteboard")
    func insertTextHappyPath() async throws {
        // The cohesive operation: pasteboard ends up with original contents,
        // capability sees the down + up post pair. Uses `skipPostForTesting`
        // so the real `CGEvent.post` doesn't fire into the test runner's
        // active session, and `setStatusForTesting(.granted)` to pin the gate
        // open regardless of host TCC state.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        let manager = TextInsertionManager(accessibility: accessibility)

        let preTestSnapshot = manager.savePasteboard()
        defer { manager.restorePasteboard(preTestSnapshot) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        try await manager.insertText("transcribed")

        #expect(pasteboard.string(forType: .string) == "original")
        #expect(accessibility.postedEventCountForTesting == 2)
    }

    @MainActor
    @Test("insertText restores pasteboard even when capability throws")
    func insertTextRestoresOnCapabilityThrow() async {
        // The load-bearing failure-mode invariant: if the post throws, the
        // transcription must not be left in the user's clipboard. Without this
        // guarantee, a runtime Accessibility revocation would silently leak
        // the transcription into whatever the user pastes next.
        let accessibility = AccessibilityCapability()
        accessibility.setStatusForTesting(.denied)  // forces postKeyEvent to throw .notGranted
        let manager = TextInsertionManager(accessibility: accessibility)

        let preTestSnapshot = manager.savePasteboard()
        defer { manager.restorePasteboard(preTestSnapshot) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        await #expect(throws: AccessibilityCapabilityError.self) {
            try await manager.insertText("transcribed")
        }
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @MainActor
    @Test("insertText skips paste entirely when the focused target is non-editable")
    func insertTextSkipsNonEditableTarget() async {
        // The paste guard (planning 0001), acceptance criterion 1: a clearly
        // non-editable target gets NO ⌘V and the clipboard is never touched —
        // not even written-then-restored. The throw is what surfaces the
        // "No text field focused" signal via FreeFlowSession.errors.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .nonEditable
        let manager = TextInsertionManager(accessibility: accessibility)

        let preTestSnapshot = manager.savePasteboard()
        defer { manager.restorePasteboard(preTestSnapshot) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let changeCountBefore = pasteboard.changeCount

        await #expect(throws: TextInsertionError.self) {
            try await manager.insertText("transcribed")
        }
        #expect(pasteboard.string(forType: .string) == "original")
        #expect(pasteboard.changeCount == changeCountBefore)  // untouched, not restored
        #expect(accessibility.postedEventCountForTesting == 0)
    }

    @MainActor
    @Test("insertText fails open and pastes when the focused target is unknown", arguments: [
        FocusedTargetClassification.unknown, FocusedTargetClassification.editable
    ])
    func insertTextPastesForUnknownOrEditable(classification: FocusedTargetClassification) async throws {
        // Acceptance criteria 2 + 3: an editable target pastes as before, and
        // an undeterminable role must behave identically (fail OPEN) — failing
        // closed would regress dictation in apps with poor AX exposure.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = classification
        let manager = TextInsertionManager(accessibility: accessibility)

        let preTestSnapshot = manager.savePasteboard()
        defer { manager.restorePasteboard(preTestSnapshot) }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        try await manager.insertText("transcribed")

        #expect(pasteboard.string(forType: .string) == "original")
        #expect(accessibility.postedEventCountForTesting == 2)
    }

    @MainActor
    @Test("insertText with empty pasteboard snapshot still clears + restores cleanly")
    func insertTextEmptyPasteboard() async throws {
        // Edge case: nothing in the user's clipboard to begin with. Snapshot
        // has zero items; restore must produce an empty pasteboard, not crash
        // and not leave the transcription behind.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        let manager = TextInsertionManager(accessibility: accessibility)

        let preTestSnapshot = manager.savePasteboard()
        defer { manager.restorePasteboard(preTestSnapshot) }

        NSPasteboard.general.clearContents()
        try await manager.insertText("transcribed")
        #expect(NSPasteboard.general.string(forType: .string) == nil)
    }
}
