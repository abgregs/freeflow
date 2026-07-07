# planning/

Active and future work. Read this first when planning a new task; updated as work moves.

Planning lives in three layers:

1. **The V1 sprint** — [milestones.md](milestones.md) (M1–M11): the one-time scaffolding build-out to a usable, shippable V1. It has an *end* (M11). [walking-skeleton.md](walking-skeleton.md) is M1 in detail.
2. **The status log** — [current-focus.md](current-focus.md): what's in flight and what just shipped.
3. **The post-V1 backlog** — the numbered `NNNN_` specs: enhancements and follow-ups that build *on top of* the V1 foundation, not new milestones. Some were deferred out of a milestone (`0003`/`0004` from M8); others are fresh ideas. (The **Open items** at the bottom are a looser holding area for post-V1 ideas.)

- [milestones.md](milestones.md) — the M1–M11 V1 sprint, greenfield to public release
- [walking-skeleton.md](walking-skeleton.md) — the first milestone in detail: a runnable menu bar app that does nothing useful
- [current-focus.md](current-focus.md) — what's actively in flight right now; updated as work moves
- [0001_focused-element-paste-guard.md](0001_focused-element-paste-guard.md) — **landed 2026-06-10**: guard the paste against non-editable focus targets via a read-only AX role check; spec retained as the record
- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) — detailed spec for a queued roadmap item: a floating, non-activating "recording…" status indicator (deferred)
- [0003_pause-media-while-dictating.md](0003_pause-media-while-dictating.md) — detailed spec for a queued roadmap item: pause now-playing media during a recording, resume after (deferred out of M8)
- [0004_model-loading-indicator.md](0004_model-loading-indicator.md) — detailed spec for a queued follow-up: surface model-loading ("warming up") state in the menu bar so early dictation isn't a silent fail (deferred from M8)
- [0005_release-pipeline-security.md](0005_release-pipeline-security.md) — security checklist the M11 release pipeline must incorporate (workflow hardening, secrets, artifact integrity); feeds M11, from the 2026-06 security review
- [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md) — runtime findings from the same review: the event tap `.listenOnly` hardening (least privilege) **landed 2026-06-17, verified on-device and shipped in v0.1.0**, plus the model-cache / no-sandbox trade-offs on record (the pasteboard-transit trade-off was eliminated by 0011)
- [0007_transient-pasteboard-markers.md](0007_transient-pasteboard-markers.md) — **landed 2026-06-12; superseded 2026-06-18 by 0011** (insertion no longer touches the clipboard, so the markers are removed): both pasteboard writes carried the nspasteboard.org transient/concealed types so well-behaved clipboard managers skipped recording dictations
- [0008_custom-dictionary-redesign.md](0008_custom-dictionary-redesign.md) — cut the V1 dictionary UI (prompt-echo bug pastes unspoken terms; 224-token ceiling blocks role packs) and redesign as two tiers: budgeted prompt biasing + deterministic post-processing with role packs. **The removal task landed 2026-06-12; the redesign remains queued.**
- [0009_sparkle-auto-update.md](0009_sparkle-auto-update.md) — add the Sparkle framework for in-app "Update available" notifications on the DMG channel; the release workflow publishes a signed appcast per tag. Closes the V1 update gap.
- [0010_relocate-model-cache.md](0010_relocate-model-cache.md) — **shipped in v0.1.0**: downloads the WhisperKit model under `~/Library/Application Support/FreeFlow` instead of WhisperKit's `~/Documents` default, so first launch doesn't trigger a Documents-folder TCC prompt or clutter the user's Documents.
- [0011_keystroke-injection.md](0011_keystroke-injection.md) — **shipped in v0.1.0**: replaced clipboard-paste insertion with Unicode keystroke injection (`CGEvent.keyboardSetUnicodeString`), eliminating the clipboard-restore race by construction (and the clipboard-privacy exposure); supersedes 0007; foundation for future streaming.
- [0012_onboarding-permissions-polish.md](0012_onboarding-permissions-polish.md) — post-V1 polish for two first-run permissions rough edges: a freshly-granted Accessibility status not reflecting until repeated Refresh (probe retry-with-settle), and no on-demand way to re-open onboarding (a "Permissions…" menu item). Not a V1 blocker.
- [0013_release-automation.md](0013_release-automation.md) — automate the last manual release steps: publish the `CHANGELOG.md` section as the GitHub Release notes and auto-bump the Homebrew tap's cask on each tag (via a scoped cross-repo token). The tap repo stays — Homebrew mandates the `homebrew-` prefix and clones the whole tap per user — but becomes a generated artifact. Combines the changelog wiring and the deferred cask-bump automation.
- [0014_test-coverage-and-ci.md](0014_test-coverage-and-ci.md) — harden the test surface from a testing-focused review (the suite is strong, not theater): run the 99-test suite in CI as a required check (today nothing runs `swift test` on PRs), then close four content gaps it leaves open — the transcription empty-prompt retry fallback, the `AppState` session→UI wiring, `AudioCaptureManager.convert` error/content paths, and a few minor branches. No new product behavior.
- [0015_automated-doc-sync.md](0015_automated-doc-sync.md) — **landed 2026-07-03**: retire the project-scoped `brief`/`debrief` skills (their metadata is injected into every Claude Code session — a harness-specific workflow imposed on contributors, and doc upkeep pushed onto them) and make the contributor guidance harness-neutral; doc/code drift moves to a scheduled maintainer routine that reviews new commits, applies high-confidence doc updates behind an adversarial review pass, and opens a PR with ambiguous findings flagged for the maintainer.
- [0016_recording-sound-cues.md](0016_recording-sound-cues.md) — audible begin/end cues for recording behind a `playFeedbackSounds` setting; the audio sibling of the HUD, another observer of the state seam. From the 2026-07-06 UX review.
- [0017_cancel-recording.md](0017_cancel-recording.md) — an escape hatch to discard an in-flight recording (`.recording → .idle`, no transcription, no paste); the trigger choice must respect the 0006 `.listenOnly`/`.flagsChanged`-only privacy posture. From the 2026-07-06 UX review.
- [0018_transient-error-toasts.md](0018_transient-error-toasts.md) — graduate cycle errors into a transient, actionable toast on the recording HUD (the richer error surface 0002 reserves); menu row stays as the lingering record. Depends on 0002. From the 2026-07-06 UX review.
- [0019_last-transcript-recovery.md](0019_last-transcript-recovery.md) — keep the last transcription in memory and add a "Copy Last Transcription" menu item, so a failed or misdirected paste doesn't force re-dictating; memory-only, never logged. From the 2026-07-06 UX review.
- [0020_mic-level-meter.md](0020_mic-level-meter.md) — live input-level indicator in the HUD so silent-mic capture is visible *during* recording instead of a post-hoc "returned no text"; level computed inside `MicrophoneCapability`. Depends on 0002. From the 2026-07-06 UX review.
- [0021_model-picker.md](0021_model-picker.md) — promote the model-picker open item to a spec: `Settings.selectedModel` + curated `Constants` list + off-cycle WhisperKit reload. Depends on 0004 (a switch re-enters the load window). From the 2026-07-06 UX review.

Detailed specs for individual items live in their own files — a milestone (like [walking-skeleton.md](walking-skeleton.md) for M1) or a backlog item (the `NNNN_` files). The `NNNN_` prefix sorts the backlog roughly by intended order, not a strict queue.

## Groupings — items that could share a PR

Several backlog items compose (surfaced by the 2026-07-06 UX review):

- **The feedback layer** — [0002](0002_recording-indicator-hud.md) (the HUD, the visual anchor), [0004](0004_model-loading-indicator.md), [0016](0016_recording-sound-cues.md), [0018](0018_transient-error-toasts.md), and [0020](0020_mic-level-meter.md) are all additional observers of the same `AppState` seam ([../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)) — no architectural change, purely additive renderers. [0018](0018_transient-error-toasts.md) and [0020](0020_mic-level-meter.md) render *inside* the 0002 panel, so those three are natural to land as a single PR; [0004](0004_model-loading-indicator.md) and [0016](0016_recording-sound-cues.md) are independent riders of the same seam and can land separately in any order.
- **The model pipeline pair** — [0004](0004_model-loading-indicator.md) before [0021](0021_model-picker.md): the picker's model switch re-enters exactly the download/load window 0004 makes visible.
- **Standalone** — [0012](0012_onboarding-permissions-polish.md), [0017](0017_cancel-recording.md), [0019](0019_last-transcript-recovery.md), [0003](0003_pause-media-while-dictating.md) have no ordering dependencies among the above.

## Open items / TODOs

These are tracked here until they're picked up into an active milestone or moved to `requirements/`:

- **Settings UI for Fn key warning**: parallel to the existing Caps Lock + Hold warning.
- **Prominent live-reconfiguration notice**: M9 surfaces the "new key now stops the recording" message in the menu dropdown; an always-visible version rides the recording HUD ([0002_recording-indicator-hud.md](0002_recording-indicator-hud.md)).
- **Model picker in Settings**: promoted to [0021_model-picker.md](0021_model-picker.md) (2026-07-06).
- **Rename `TranscriptionService` → `TranscriptionManager`**: align with the `Manager` suffix convention chosen for cycle collaborators (see [../conventions/swift-style.md](../conventions/swift-style.md)). Standalone PR — touch the type name, file name, and the AppDelegate/session construction sites.
- **macOS 16 pasteboard privacy**: *moot as of [0011](0011_keystroke-injection.md)* — Apple is rolling out prompts for programmatic pasteboard reads (preview in macOS 15.4; enforcement expected in macOS 16), but Free Flow no longer reads or writes the pasteboard (insertion is keystroke injection), so the prompt can't trigger. Kept for historical context.
