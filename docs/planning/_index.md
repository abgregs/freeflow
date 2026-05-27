# planning/

Active and future work. Read this first when planning a new task; update it as work progresses.

- [milestones.md](milestones.md) — ordered list of milestones from greenfield to public release
- [walking-skeleton.md](walking-skeleton.md) — the first milestone in detail: a runnable menu bar app that does nothing useful
- [current-focus.md](current-focus.md) — what's actively in flight right now; updated as work moves

## Open items / TODOs

These are tracked here until they're picked up into an active milestone or moved to `requirements/`:

- **Release automation**: GitHub Action to build → sign with Developer ID → notarize → attach DMG to release. See [../architecture/distribution.md](../architecture/distribution.md).
- **Homebrew cask**: tap repo + cask formula pointing at GitHub Releases.
- **Apple Developer Program enrollment**: required for Developer ID signing and notarization ($99/yr).
- **Settings UI for `doubleTapWindowMs`**: a slider for users who want to tune the double-tap window. Currently fixed at 400 ms.
- **Settings UI for Fn key warning**: parallel to the existing Caps Lock + Hold warning.
- **Mid-cycle settings change visual feedback**: when `pendingActivationRestart` is set, briefly show the user that their change will apply after the current recording.
