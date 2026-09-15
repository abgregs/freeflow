# Design direction: River

The identity brief for the design phase that follows the naming decision ([../planning/0027_project-naming.md](../planning/0027_project-naming.md)). It fixes the *direction* — what the app should feel like and why — so that the icon, motion, sound, and page work that follows makes decisions against the same idea. It is not a spec; each surface below gets its own numbered planning item when it is picked up.

## The idea

**Text flows in and follows you.** You speak; words arrive at the cursor in whatever app you are in. The name is the metaphor: a river is continuous, goes wherever the ground goes, and is calm at the surface while moving underneath. The 0025 streaming-dictation direction (continuous insertion instead of paste-at-the-end) makes this literal later; the identity should anticipate it now.

**How it should feel:** sharp, snappy, responsive. Motion is *subtle yet striking* — fluid, never bouncy — and appears only where it carries meaning. The app is a utility that lives in the menu bar; it should be invisible until you call it and unmistakable while it is working.

## Principles

1. **Motion is state, never decoration.** Every animation maps to a transition on the cycle state seam ([../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)): `.idle → .recording → .processing → .idle`, plus `.loading` and errors. If a transition has no motion, that is a decision; if a motion has no transition, it goes.
2. **Never steal focus.** The HUD is a non-activating panel that must not become key ([../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md)). No surface may pull the caret away from where the text is about to land. Identity work lives inside that constraint, not around it.
3. **Fluid, not bouncy.** Continuous easing curves and crossfades over springs and overshoot. The water vocabulary is *current, ripple, flow* — restrained, low amplitude, short. A recording is not a splash.
4. **Platform first.** SF Symbols and system materials by default; light and dark appearance; Reduce Motion honored (motion degrades to a crossfade, never to nothing); no custom fonts. Custom assets earn their place per surface, below.
5. **Quiet by default.** No sound unless opted in (the 0016 toggle), no persistent panels, no nagging. The HUD fades out on `.idle`; errors are transient toasts, not pinned warnings (0018). Cutting an animation is always an acceptable outcome of a review.

## Surfaces

| Surface | Today | Direction |
|---|---|---|
| **App icon** | None — `Sources/River/Resources` holds only the plist and entitlements; the bundle shows the generic icon. | Greenfield. A single strong mark: a current or river line inside the macOS squircle, one accent color on a dark or light ground. Must read at Finder and Dock sizes; the menu bar does *not* use it. First deliverable of the phase, because the DMG, the page, and the onboarding window all need it. |
| **Menu bar glyphs** | SF Symbols chosen per state in `MenuBarPresentation`; the warning glyph overrides only the idle icon. | Keep template-glyph behavior (monochrome, auto-tinted). Decide between a curated SF Symbol set and a custom template family derived from the icon mark. The recording state should be readable at a glance from across the screen. |
| **Recording HUD** | `RecordingIndicatorView`: `mic.fill`, live level meter (0020), error toasts (0018), fade in/out. | The centerpiece. `.recording` = the level meter rendered as a flowing line driven by real input; `.processing` = a calm current, no spinner; the insert moment = text arriving, once streaming exists. Fix the deferred polish here: the sub-second gate gap at `.loading → .ready`, the lingering menu-bar warning after a gate-declined activation, and the 0017 canceled-notice bleed. |
| **Sound cues** | System sounds behind `playFeedbackSounds` (0016), with a distinct cancel cue (0017). | Three short custom cues (start, stop, cancel) that share one timbre — crisp, not watery; under 200 ms; identical loudness. Move the sound names into `Constants` when replacing them (open follow-up on PR #31). |
| **Onboarding and Settings** | Functional SwiftUI windows; onboarding is the permissions walkthrough. | Copy and rhythm pass, the icon in the onboarding header, and the 0004 loading-copy refinement ("Preparing model…" instead of "Loading…"). No new chrome. |
| **README / GitHub page** | Text README with two screenshots. | **Deferred until the in-app identity exists.** Then: color, the icon, a short looping capture of the HUD, and the install command above the fold. Do not design the page before the app. |
| **DMG background** | Plain. | The icon and an arrow. Last. |

## Constraints to respect

- The three architecture seams stay put: identity work is additional observers of `AppState`, never new callers into `RiverSession` ([../architecture/river-session.md](../architecture/river-session.md)).
- Every timing that matters (fade durations, cue lengths) lives in `Constants`, not inline, per `AGENTS.md` rule 5.
- No new dependencies for animation or audio without a decision record in [../decisions/](../decisions/_index.md); SwiftUI and AVFoundation cover the surfaces above.
- Nothing here changes the bundle ID, the feed URL, or the cask — those are fixed by [0027](../planning/0027_project-naming.md).

## Open decisions

Settle these in the phase and record the answer here or in the surface's planning item.

- **Accent color:** one color, or a light/dark pair? Water-adjacent (teal/blue) is the obvious read; decide whether obvious is right.
- **Glyphs:** SF Symbols only, or a custom template family?
- **Motion implementation:** SwiftUI animations throughout, or Core Animation for the HUD line?
- **Cues:** custom recordings, or synthesized in code for zero asset weight?
- **Streaming preview:** should the HUD hint at continuous insertion before 0025 ships, or stay honest about paste-at-the-end?

## Sequence

After the first River build has been smoked on-device: icon and menu bar glyphs → HUD motion pass (with the deferred polish) → sound cues → onboarding and Settings pass → README/page → DMG background. Each step is one planning item (`0028` onward) and one PR; none of them blocks a release.

## Related

- [../planning/0027_project-naming.md](../planning/0027_project-naming.md) — why the name, and the identifiers the design must not touch
- [../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md), [0018](../planning/0018_transient-error-toasts.md), [0020](../planning/0020_mic-level-meter.md) — the HUD, its toasts, and its meter
- [../planning/0016_recording-sound-cues.md](../planning/0016_recording-sound-cues.md) — the cue toggle and the current sounds
- [../planning/0004_model-loading-indicator.md](../planning/0004_model-loading-indicator.md) — the loading-copy refinement
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the seam every surface observes
