import CoreGraphics
import Foundation
import os

enum TextInsertionError: Error, LocalizedError {
    case noEditableTarget

    var errorDescription: String? {
        switch self {
        case .noEditableTarget:
            return "No text field focused — click into a text field and try again."
        }
    }
}

@MainActor
final class TextInsertionManager {
    private let accessibility: AccessibilityCapability
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "insert")

    init(accessibility: AccessibilityCapability) {
        self.accessibility = accessibility
    }

    /// Inserts `text` at the cursor by synthesizing Unicode key events — the app
    /// never touches the clipboard, so there is no snapshot/restore and the
    /// clipboard-restore race is gone *by construction* (planning 0011). The
    /// keystrokes route through `AccessibilityCapability.postKeyEvent`, the one
    /// `CGEvent.post` site, so the `.granted` gate and the silent-no-op probe
    /// still apply.
    ///
    /// Skips (throwing `TextInsertionError.noEditableTarget`) when the focused
    /// element is clearly non-editable — the insertion guard (planning 0001).
    func insertText(_ text: String) async throws {
        // Insertion guard (planning 0001): typing into a non-editable target is
        // indistinguishable from success after the fact, so check the focused
        // element's role first. `.unknown` fails open — only a clearly
        // non-editable role skips.
        if accessibility.classifyFocusedTarget() == .nonEditable {
            logger.info("insertText: skipped — focused element is not editable")
            throw TextInsertionError.noEditableTarget
        }
        let chunks = Self.chunk(text, maxUnits: Constants.keystrokeChunkUnits)
        logger.info("insertText: injecting \(text.count, privacy: .public) chars in \(chunks.count, privacy: .public) chunk(s)")
        do {
            for chunk in chunks {
                try accessibility.postKeyEvent(Self.makeUnicodeKeyEvent(chunk, keyDown: true))
                try accessibility.postKeyEvent(Self.makeUnicodeKeyEvent(chunk, keyDown: false))
            }
            logger.info("insertText: done")
        } catch {
            // The only throws here are `postKeyEvent`'s `.notGranted` / `.silentNoOp`,
            // which fire on the *first* event (the gate + first-use probe) — before
            // any character is injected. There is no clipboard to restore. Log and
            // rethrow so `FreeFlowSession` surfaces the error.
            logger.error("insertText: failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    // internal for testability — splits `text` into chunks of at most `maxUnits`
    // UTF-16 code units without ever splitting a grapheme cluster, so surrogate
    // pairs and combining marks stay intact within a single event.
    // `keyboardSetUnicodeString` is unreliable past ~20 units in some apps, hence
    // the chunking; the post is exercised via `postedEventCountForTesting`.
    static func chunk(_ text: String, maxUnits: Int) -> [String] {
        guard maxUnits > 0 else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var current = ""
        var currentUnits = 0
        for character in text {                 // Character == grapheme cluster
            let units = String(character).utf16.count
            if currentUnits + units > maxUnits, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentUnits = 0
            }
            current.append(character)
            currentUnits += units
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // Builds a key event carrying the literal characters. `keyboardSetUnicodeString`
    // overrides the virtual key, so the keycode (0) is a placeholder. The string
    // is set on both the down and up events (the common pattern); apps insert on
    // key-down and ignore the up's string. Force-unwrap matches the CGEvent /
    // AVAudioFormat pattern elsewhere — the init only returns nil for an invalid
    // keycode, and 0 is valid.
    private static func makeUnicodeKeyEvent(_ string: String, keyDown: Bool) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)!
        let utf16 = Array(string.utf16)
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        return event
    }
}
