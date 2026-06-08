# planning/

Active and future work. Read this first when planning a new task; update it as work progresses.

- [milestones.md](milestones.md) — ordered list of milestones from greenfield to public release
- [walking-skeleton.md](walking-skeleton.md) — the first milestone in detail: a runnable menu bar app that does nothing useful
- [current-focus.md](current-focus.md) — what's actively in flight right now; updated as work moves
- [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md) — detailed spec for a queued roadmap item: guard the paste against non-editable focus targets
- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) — detailed spec for a queued roadmap item: a floating, non-activating "recording…" status indicator (deferred)
- [0003_pause-media-while-dictating.md](0003_pause-media-while-dictating.md) — detailed spec for a queued roadmap item: pause now-playing media during a recording, resume after (deferred out of M8)

Detailed specs for individual roadmap items live in their own files (like [walking-skeleton.md](walking-skeleton.md) for M1). New queued items use an ordered `NNNN_` filename prefix (`0001_`, `0002_`, …) so they sort in execution order.

## Open items / TODOs

These are tracked here until they're picked up into an active milestone or moved to `requirements/`:

- **Release automation**: GitHub Action to build → sign with Developer ID → notarize → attach DMG to release. See [../architecture/distribution.md](../architecture/distribution.md).
- **Homebrew cask**: tap repo + cask formula pointing at GitHub Releases.
- **Apple Developer Program enrollment**: required for Developer ID signing and notarization ($99/yr).
- **Settings UI for `doubleTapWindowMs`**: a slider for users who want to tune the double-tap window. Currently fixed at 400 ms.
- **Settings UI for Fn key warning**: parallel to the existing Caps Lock + Hold warning.
- **Mid-cycle settings change visual feedback**: when `pendingActivationRestart` is set, briefly show the user that their change will apply after the current recording.
- **Model picker in Settings**: deferred out of M8 (needs a `Constants` model list + live WhisperKit reload off-cycle). Lands with the M9+ settings round alongside the activation-mode picker.
- **Rename `TranscriptionService` → `TranscriptionManager`**: align with the `Manager` suffix convention chosen for cycle collaborators (see [../conventions/swift-style.md](../conventions/swift-style.md)). Standalone PR — touch the type name, file name, and the AppDelegate/session construction sites.
