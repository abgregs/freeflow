# architecture/

How Free Flow is structured and why. Read in order on a first pass; reference individually thereafter.

- [overview.md](overview.md) — process model, target audience, the broad shape of the app
- [free-flow-session.md](free-flow-session.md) — the deep module that owns one full activation-to-paste cycle; consumes managers, holds the state machine, applies deferred reconfiguration
- [app-state-and-menu-bar.md](app-state-and-menu-bar.md) — the `AppState` Combine→`@Observable` bridge and pure `MenuBarPresentation` mapping that let the UI observe the cycle while the session stays UI-agnostic
- [capabilities.md](capabilities.md) — the per-permission modules that own both the TCC check and the OS call they gate; collapse the lying-check, silent-paste, and onboarding-too-late failure modes into structural properties
- [settings-store.md](settings-store.md) — typed read/write/observe over `UserDefaults.standard`; per-key publishers replace the global notification + filter pattern
- [free-flow-pipeline.md](free-flow-pipeline.md) — one end-to-end cycle from keypress to pasted text; the state machine
- [threading-invariant.md](threading-invariant.md) — the dedicated background thread the event tap runs on, owned by `InputMonitoringCapability`
- [permissions.md](permissions.md) — Accessibility, Microphone, Input Monitoring; what they're for; what the user must grant manually
- [configuration.md](configuration.md) — `Constants` vs. `SettingsStore`; live-apply via session subscription
- [distribution.md](distribution.md) — signed `.app` bundle, DMG, Homebrew cask; the role of the developer signing identity vs. the local dev identity
