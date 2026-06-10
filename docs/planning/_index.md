# planning/

Active and future work. Read this first when planning a new task; update it as work progresses.

Planning lives in three layers:

1. **The V1 sprint** — [milestones.md](milestones.md) (M1–M11): the one-time scaffolding build-out to a usable, shippable V1. It has an *end* (M11). [walking-skeleton.md](walking-skeleton.md) is M1 in detail.
2. **The status log** — [current-focus.md](current-focus.md): what's in flight and what just shipped.
3. **The post-V1 backlog** — the numbered `NNNN_` specs: enhancements and follow-ups that build *on top of* the V1 foundation, not new milestones. Some were deferred out of a milestone (`0003`/`0004` from M8); others are fresh ideas. (The **Open items** at the bottom are a looser holding area — a few feed M10/M11, the rest are post-V1.)

- [milestones.md](milestones.md) — the M1–M11 V1 sprint, greenfield to public release
- [walking-skeleton.md](walking-skeleton.md) — the first milestone in detail: a runnable menu bar app that does nothing useful
- [current-focus.md](current-focus.md) — what's actively in flight right now; updated as work moves
- [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md) — detailed spec for a queued roadmap item: guard the paste against non-editable focus targets
- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) — detailed spec for a queued roadmap item: a floating, non-activating "recording…" status indicator (deferred)
- [0003_pause-media-while-dictating.md](0003_pause-media-while-dictating.md) — detailed spec for a queued roadmap item: pause now-playing media during a recording, resume after (deferred out of M8)
- [0004_model-loading-indicator.md](0004_model-loading-indicator.md) — detailed spec for a queued follow-up: surface model-loading ("warming up") state in the menu bar so early dictation isn't a silent fail (deferred from M8)

Detailed specs for individual items live in their own files — a milestone (like [walking-skeleton.md](walking-skeleton.md) for M1) or a backlog item (the `NNNN_` files). The `NNNN_` prefix sorts the backlog roughly by intended order, not a strict queue.

## Open items / TODOs

These are tracked here until they're picked up into an active milestone or moved to `requirements/`:

- **Release automation**: GitHub Action to build → sign with Developer ID → notarize → attach DMG to release. See [../architecture/distribution.md](../architecture/distribution.md).
- **Homebrew cask**: tap repo + cask formula pointing at GitHub Releases.
- **Apple Developer Program enrollment**: required for Developer ID signing and notarization ($99/yr).
- **Settings UI for Fn key warning**: parallel to the existing Caps Lock + Hold warning.
- **Prominent live-reconfiguration notice**: M9 surfaces the "new key now stops the recording" message in the menu dropdown; an always-visible version rides the recording HUD ([0002_recording-indicator-hud.md](0002_recording-indicator-hud.md)).
- **Model picker in Settings**: a `Constants` model list + off-cycle WhisperKit reload, letting speed-focused users drop back to `base.en`. Deferred through M9; future.
- **Rename `TranscriptionService` → `TranscriptionManager`**: align with the `Manager` suffix convention chosen for cycle collaborators (see [../conventions/swift-style.md](../conventions/swift-style.md)). Standalone PR — touch the type name, file name, and the AppDelegate/session construction sites.
