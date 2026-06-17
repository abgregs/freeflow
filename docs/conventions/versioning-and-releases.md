# Conventions: Versioning and Releases

How Free Flow versions and ships. The release *mechanics* (secrets, workflow steps, how to cut a release) live in the [release-pipeline runbook](../architecture/release-pipeline.md); this doc is the *protocol* — what to tag, how to number, and what a release means per channel.

## Releases are tag-driven

Every release is a **`vX.Y.Z` git tag pushed to `main`**. Pushing the tag is the entire action — [`.github/workflows/release.yml`](../../.github/workflows/release.yml) handles build, sign, notarize, and publish. No manual building or uploading.

```bash
git tag v0.2.0 && git push origin v0.2.0
```

- **The tag is the single source of truth for the version.** The workflow stamps it into `Info.plist` at build time — never hand-edit a version in source.
- **Tag from `main` only.** `main` is the protected, always-green branch; a release captures one specific commit on it. Don't tag a feature branch.
- **Tags are immutable.** `v*` deletion and force-push are blocked by a ruleset ([git.md](git.md)). To fix a bad release, ship the next version — never move or reuse a tag.

## Semantic Versioning

`MAJOR.MINOR.PATCH`:

| Bump | When | Example |
|---|---|---|
| **PATCH** | bug fixes, no behavior change | `0.1.0 → 0.1.1` |
| **MINOR** | new features, backward-compatible | `0.1.0 → 0.2.0` |
| **MAJOR** | breaking changes, or the deliberate "now stable" line | `0.x → 1.0.0` |

- **`0.x.y`** (where we start) signals "early, anything may change." The first public release is `0.1.0`.
- **`1.0.0`** is a statement of confidence, not a technical trigger — bump to it when *you* decide the app is stable.

## Pre-release / test tags

A suffixed tag — `vX.Y.Z-rc1`, `-beta1` — publishes as a GitHub **pre-release**. The workflow stamps the numeric core (`0.2.0`) into `CFBundleShortVersionString` and marks the release pre-release automatically. This is the **safe way to exercise the pipeline** before a real release (there is no dry-run, and tags can't be deleted).

## Two version fields (macOS)

An `.app` carries two version fields, serving different masters:

- **`CFBundleShortVersionString`** — the human "marketing" version (`0.2.0`), from the tag. What users see.
- **`CFBundleVersion`** — an internal **build number** that must only ever increase. The workflow sets it to the GitHub run number, so it climbs automatically. **Why it matters:** an auto-updater ([Sparkle](../planning/0009_sparkle-auto-update.md)) compares *this* field to decide "is there something newer," so it must stay monotonic — never reset it.

## What a release means per channel

| Channel | How users get the new version |
|---|---|
| **DMG download** | Manual — re-download from the Release page (no notification until [Sparkle](../planning/0009_sparkle-auto-update.md) lands) |
| **Homebrew** | `brew upgrade` (pull-based) — **requires bumping the cask** (`version` + `sha256`) in the tap each release |
| **Source build** | `git pull` + `make install` |

See [distribution.md](../architecture/distribution.md) for the full update story.

## Related

- [../architecture/release-pipeline.md](../architecture/release-pipeline.md) — the pipeline that runs on a tag; secrets and setup
- [../architecture/distribution.md](../architecture/distribution.md) — channels, signing identities, update delivery
- [git.md](git.md) — tag protection and the merge-to-`main` flow
- [../planning/0009_sparkle-auto-update.md](../planning/0009_sparkle-auto-update.md) — planned in-app auto-update
