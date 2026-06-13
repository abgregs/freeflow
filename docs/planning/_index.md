# planning/

Active and future work. Read this first when planning a new task; update it as work progresses.

Planning lives in three layers:

1. **The V1 sprint** — [milestones.md](milestones.md) (M1–M11): the one-time scaffolding build-out to a usable, shippable V1. It has an *end* (M11). [walking-skeleton.md](walking-skeleton.md) is M1 in detail.
2. **The status log** — [current-focus.md](current-focus.md): what's in flight and what just shipped.
3. **The post-V1 backlog** — the numbered `NNNN_` specs: enhancements and follow-ups that build *on top of* the V1 foundation, not new milestones. Some were deferred out of a milestone (`0003`/`0004` from M8); others are fresh ideas. (The **Open items** at the bottom are a looser holding area — a few feed M10/M11, the rest are post-V1.)

- [milestones.md](milestones.md) — the M1–M11 V1 sprint, greenfield to public release
- [walking-skeleton.md](walking-skeleton.md) — the first milestone in detail: a runnable menu bar app that does nothing useful
- [current-focus.md](current-focus.md) — what's actively in flight right now; updated as work moves
- [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md) — **landed 2026-06-10**: guard the paste against non-editable focus targets via a read-only AX role check; spec retained as the record
- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) — detailed spec for a queued roadmap item: a floating, non-activating "recording…" status indicator (deferred)
- [0003_pause-media-while-dictating.md](0003_pause-media-while-dictating.md) — detailed spec for a queued roadmap item: pause now-playing media during a recording, resume after (deferred out of M8)
- [0004_model-loading-indicator.md](0004_model-loading-indicator.md) — detailed spec for a queued follow-up: surface model-loading ("warming up") state in the menu bar so early dictation isn't a silent fail (deferred from M8)
- [0005_release-pipeline-security.md](0005_release-pipeline-security.md) — security checklist the M11 release pipeline must incorporate (workflow hardening, secrets, artifact integrity); feeds M11, from the 2026-06 security review
- [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md) — runtime findings from the same review: switch the event tap to `.listenOnly` (least privilege), plus the accepted pasteboard / model-cache / no-sandbox trade-offs on record
- [0007_transient-pasteboard-markers.md](0007_transient-pasteboard-markers.md) — **landed 2026-06-12**: both pasteboard writes carry the nspasteboard.org transient/concealed types so well-behaved clipboard managers stop recording dictations; upgrades 0006's pasteboard trade-off
- [0008_custom-dictionary-redesign.md](0008_custom-dictionary-redesign.md) — cut the V1 dictionary UI (prompt-echo bug pastes unspoken terms; 224-token ceiling blocks role packs) and redesign as two tiers: budgeted prompt biasing + deterministic post-processing with role packs. **The removal task landed 2026-06-12; the redesign remains queued.**

Detailed specs for individual items live in their own files — a milestone (like [walking-skeleton.md](walking-skeleton.md) for M1) or a backlog item (the `NNNN_` files). The `NNNN_` prefix sorts the backlog roughly by intended order, not a strict queue.

## Open items / TODOs

These are tracked here until they're picked up into an active milestone or moved to `requirements/`:

- **Release automation**: GitHub Action to build → sign with Developer ID → notarize → attach DMG to release. See [../architecture/distribution.md](../architecture/distribution.md). Must satisfy the security checklist in [0005_release-pipeline-security.md](0005_release-pipeline-security.md).
- **Homebrew cask**: tap repo + cask formula pointing at GitHub Releases.
- **Apple Developer Program enrollment**: required for Developer ID signing and notarization ($99/yr).
- **Settings UI for Fn key warning**: parallel to the existing Caps Lock + Hold warning.
- **Prominent live-reconfiguration notice**: M9 surfaces the "new key now stops the recording" message in the menu dropdown; an always-visible version rides the recording HUD ([0002_recording-indicator-hud.md](0002_recording-indicator-hud.md)).
- **Model picker in Settings**: a `Constants` model list + off-cycle WhisperKit reload, letting speed-focused users drop back to `base.en`. Deferred through M9; future.
- **Rename `TranscriptionService` → `TranscriptionManager`**: align with the `Manager` suffix convention chosen for cycle collaborators (see [../conventions/swift-style.md](../conventions/swift-style.md)). Standalone PR — touch the type name, file name, and the AppDelegate/session construction sites.
- **macOS 16 pasteboard privacy**: Apple is rolling out prompts for programmatic pasteboard reads (preview shipped in macOS 15.4; enforcement expected in macOS 16). Free Flow's pre-paste snapshot is a programmatic read and may trigger the prompt — adopt the new `NSPasteboard.accessBehavior` / `detect` APIs and verify against the betas. Also raises the floor against pasteboard-polling snoopers, complementing [0007_transient-pasteboard-markers.md](0007_transient-pasteboard-markers.md).
