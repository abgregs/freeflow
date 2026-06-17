# conventions/

How code is written in Free Flow. Read what's relevant before changing code in that area.

- [swift-style.md](swift-style.md) — naming, access control, file layout, when to extract types
- [logging.md](logging.md) — `os.Logger` usage; user content protected by omission, error strings path-redacted via `LogRedaction`
- [persistence.md](persistence.md) — `UserDefaults` keys, defaults, observation
- [tests.md](tests.md) — `swift-testing` framework, test patterns, what's exercised and what isn't
- [git.md](git.md) — branches, conventional commits, stacked PRs, what touches `main`
- [versioning-and-releases.md](versioning-and-releases.md) — tag-driven release protocol, SemVer rules, the two macOS version fields, per-channel update behavior
- [anti-patterns.md](anti-patterns.md) — explicit "do not do this," with the why
