import AppKit
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
    /// Captures the full pasteboard (all items, all types) as opaque `Data` so
    /// non-string content (RTF, images, custom UTIs) round-trips unchanged.
    struct PasteboardSnapshot: Equatable {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private let accessibility: AccessibilityCapability
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "insert")

    init(accessibility: AccessibilityCapability) {
        self.accessibility = accessibility
    }

    /// Saves the pasteboard, writes `text`, posts a synthesized ⌘V via the
    /// capability, sleeps `Constants.clipboardRestoreDelay` so the target app's
    /// paste handler can pull the new contents in, then restores the original
    /// pasteboard. On any throw before the restore, the original pasteboard is
    /// still restored — leaving the transcription in the user's clipboard
    /// would be a worse failure than the original paste error.
    ///
    /// Skips entirely (throwing `TextInsertionError.noEditableTarget`) when
    /// the focused element is clearly non-editable. The guard runs before the
    /// pasteboard is touched, so a skipped paste leaves the clipboard intact
    /// and never triggers the capability's first-use probe.
    func insertText(_ text: String) async throws {
        // Paste guard (planning 0001): a ⌘V into a non-editable target is
        // indistinguishable from success after the fact, so check the focused
        // element's role first. `.unknown` fails open — only a clearly
        // non-editable role skips.
        if accessibility.classifyFocusedTarget() == .nonEditable {
            logger.info("insertText: skipped — focused element is not editable")
            throw TextInsertionError.noEditableTarget
        }
        let snapshot = savePasteboard()
        logger.info("insertText: starting (length=\(text.count, privacy: .public), snapshotItems=\(snapshot.items.count, privacy: .public))")
        do {
            writePasteboard(text)
            try accessibility.postKeyEvent(Self.makeCommandV(down: true))
            try accessibility.postKeyEvent(Self.makeCommandV(down: false))
            try await Task.sleep(nanoseconds: UInt64(Constants.clipboardRestoreDelay * 1_000_000_000))
            restorePasteboard(snapshot)
            logger.info("insertText: posted and restored pasteboard")
        } catch {
            // Post (or sleep, on cancellation) failed before the restore landed.
            // Restore immediately — the paste did not happen, so there's nothing
            // to wait for, and we must not strand the transcription in the user's
            // clipboard. Then rethrow so `FreeFlowSession` can surface the error.
            restorePasteboard(snapshot)
            logger.error("insertText: failed, pasteboard restored: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    // internal for testability — captures the full pasteboard as opaque `Data`
    // per type per item. Tests round-trip RTF + plain string to lock in that
    // non-string content survives the paste cycle.
    func savePasteboard() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = pasteboard.pasteboardItems ?? []
        let captured: [[NSPasteboard.PasteboardType: Data]] = items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
        return PasteboardSnapshot(items: captured)
    }

    // internal for testability — rewrites the captured items back onto
    // `NSPasteboard.general`. Idempotent on the system pasteboard's behalf
    // (always clears first).
    func restorePasteboard(_ snapshot: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private func writePasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // ⌘V: V is virtual keycode 9; the command modifier travels on `.flags` of
    // each key event rather than as a separate flagsChanged pair. Force-unwrap
    // matches the AVAudioFormat / CGEvent pattern elsewhere — these init paths
    // only return nil for invalid keycodes, and 9 is hardcoded.
    private static func makeCommandV(down: Bool) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)!
        event.flags = .maskCommand
        return event
    }
}
