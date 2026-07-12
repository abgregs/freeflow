# Planning: Last-Transcript Recovery (roadmap 0019)

A queued backlog item from the 2026-07-06 UX review. Keep the most recent transcription in memory and add a menu-bar **"Copy Last Transcription"** item, so a failed or misdirected paste doesn't force the user to re-dictate everything.

> **Amended by [0025](0025_streaming-dictation.md) (2026-07-11):** under streaming dictation, "the last transcription" is the *accumulated session transcript* (every segment inserted this session), not the final segment. Retention semantics here are unchanged for the one-shot mode.

## Problem

When the paste fails — no editable target ([0001](0001_focused-element-paste-guard.md)'s guard), the silent-no-op probe firing, a post error — or simply lands in the wrong field, the transcription is **gone**. The error row explains *why* it failed but cannot give the text back; the user's only recovery is to dictate the whole thing again. For long dictations this is the single most expensive failure in the app, and it's exactly the moment the user is already frustrated.

## Design: memory-only retention, user-invoked copy

- **`FreeFlowSession` retains the most recent transcription in memory** — on paste success *and* on paste failure (the failure case is the whole point). Replaced by the next cycle's result; never persisted; gone at quit. One transcript, not a history.
- **`AppState` exposes availability** (has-a-transcript, not the content) so the menu item can enable/disable; the menu gains **"Copy Last Transcription"**, which writes the text to the general pasteboard.
- **This does not violate 0011's "the app never touches the clipboard."** That is an *insertion-path* invariant — it eliminated the restore race by keeping the automated cycle off the pasteboard. A user-invoked copy is the user's own explicit command, outside the cycle. When this lands, add one clarifying line to [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) so the invariant stays crisp (cycle: never; explicit user action: allowed).
- **Privacy by omission holds:** the transcript is memory-only and never logged — `.count` at most ([../conventions/logging.md](../conventions/logging.md), anti-pattern #4).
- **Decision: re-apply the nspasteboard.org transient/concealed marker types** (removed when [0007](0007_transient-pasteboard-markers.md) was retired by 0011) to this one write, so well-behaved clipboard managers skip recording dictated content. Same privacy rationale 0007 had; likely yes.

## Acceptance criteria

1. After a paste failure of any kind, "Copy Last Transcription" puts the full transcription on the clipboard.
2. After a successful paste, the same item offers that cycle's text (useful for "paste it again elsewhere").
3. The retained transcript is replaced by the next cycle and absent before the first cycle (menu item disabled).
4. Transcript content never appears in any log line — a test pins the by-omission rule.
5. Session retention (success path, each failure path, replacement) is unit-tested; the menu wiring reuses the `AppState` observation pattern.

## What it does not do

- No transcription history, no persistence, no UI beyond the single menu item.
- No change to the insertion path — keystroke injection ([0011](0011_keystroke-injection.md)) is untouched.

## Related

- [0011_keystroke-injection.md](0011_keystroke-injection.md) — the insertion-path clipboard invariant this deliberately does not breach
- [0007_transient-pasteboard-markers.md](0007_transient-pasteboard-markers.md) — the marker precedent for the copy write
- [../conventions/logging.md](../conventions/logging.md) / [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — privacy by omission (#4)
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the seam the menu item observes
