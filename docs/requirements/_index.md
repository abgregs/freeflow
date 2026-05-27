# requirements/

What River is supposed to do. These docs describe behavior; the [architecture/](../architecture/_index.md) and [conventions/](../conventions/_index.md) folders describe how that behavior is built.

- [core-feature.md](core-feature.md) — the primary user story: hold/tap a key, speak, get text at cursor; first-launch onboarding
- [activation-key-and-mode.md](activation-key-and-mode.md) — the activation key picker, the three modes (Hold / Single Tap / Double Tap), the persistence and live-apply contract
- [supported-keys-and-limitations.md](supported-keys-and-limitations.md) — exactly which keys are pickable, which combinations are restricted or warned about, and known limitations of macOS that bound the design
- [custom-dictionary.md](custom-dictionary.md) — user-editable list of terms passed to WhisperKit as prompt tokens
