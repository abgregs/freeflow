# Planning: Release Automation — Release Notes + Homebrew Cask Bump (roadmap 0013)

The V1 release workflow ([release.yml](../../.github/workflows/release.yml)) ships the notarized DMG + SHA-256 on a `v*` tag, but two per-release steps are still manual:

1. **GitHub Release notes** are auto-generated from merged PR titles (`gh release create … --generate-notes`) — mechanical, not the curated [`CHANGELOG.md`](../../CHANGELOG.md) entry.
2. **The Homebrew cask** is bumped by hand: edit `version` + `sha256` in [`packaging/homebrew/freeflow.rb`](../../packaging/homebrew/freeflow.rb), copy it into the separate tap repo (`abgregs/homebrew-freeflow`), and push.

This closes both, so a single `git tag vX.Y.Z && git push` ships the DMG, checksum, **curated** release notes, **and** the updated cask — no manual follow-up. It resolves the automation deferred in [../../packaging/homebrew/README.md](../../packaging/homebrew/README.md) and the changelog-wiring follow-up from the v0.1.0 doc sweep.

## Why the tap stays a separate repo

The recurring question is whether the cask can live in the main `freeflow` repo instead of `homebrew-freeflow`. It can't, and shouldn't:

- **The `homebrew-` prefix is mandatory.** `brew install --cask abgregs/freeflow/freeflow` resolves the tap `abgregs/freeflow` to the repo `abgregs/homebrew-freeflow` — Homebrew hardcodes that prefix. A tap cannot be served from the `freeflow` app repo. (The prefix is also what keeps the app repo and the tap from colliding even though both end in `freeflow`.)
- **`brew tap` clones the entire tap repo to every user's machine.** A tiny cask-only repo is the correct design; folding it into `freeflow` would clone the whole app history onto each installer.

**Why:** so this roadmap does not try to eliminate the repo — it makes the repo a **generated artifact** the maintainer never edits by hand. "Everything from one repo" in practice, without fighting Homebrew's model.

## Piece 1 — Release notes from CHANGELOG.md

- Replace `--generate-notes` with the curated section: extract the `## [x.y.z]` block from `CHANGELOG.md` and pass it via `gh release create … --notes-file`. (Optionally keep `--generate-notes` too for GitHub's auto compare-link + contributor list, which it appends.)
- **Curation stays human.** Keep the `## [Unreleased]` section updated as PRs merge; at release, rename it to `## [x.y.z] - <date>` — that rename is the deliberate "these are the notes" moment — then tag. The workflow only *reads* the named section; it never writes prose.
- **Guard:** if no `## [x.y.z]` section exists for the tag, the workflow fails before publishing. **Why:** a missing changelog entry should block the release, not silently fall back to PR-title noise.

## Piece 2 — Auto-bump the Homebrew cask

- After the DMG + `.dmg.sha256` are published, render the cask and push it to the tap.
- **Source-of-truth split:** `packaging/homebrew/freeflow.rb` stays the *reviewed template* — it owns the cask's **shape** (`name`/`desc`/`depends_on`/`caveats`/`zap`/`url` pattern). The workflow substitutes the only two generated fields — `version` (from the tag) and `sha256` (read from the published `.dmg.sha256`, not recomputed) — and writes the result to `Casks/freeflow.rb` in the tap. **Why:** the cask's structure is what deserves PR review in the main repo; `version`/`sha256` are mechanical. This removes the "copy across" step while keeping the template meaningful.
- **Push target:** directly to the tap's default branch (it has no branch protection) for full automation; a PR against the tap is the cautious alternative if the tap is ever protected.
- **Tooling:** a checkout + field substitution + commit + push is sufficient; `brew bump-cask-pr` or a community cask-bump action is the heavier "blessed" alternative.

## Piece 3 — The cross-repo credential

- `release.yml`'s default `GITHUB_TOKEN` is scoped to `freeflow` only and cannot push to `homebrew-freeflow`.
- Add a **fine-grained PAT** with `contents:write` on **`homebrew-freeflow` only** (or a GitHub App installation token), stored as a repo secret. Least-privilege, revocable, single-repo scope — consistent with the credential principles in [0005](0005_release-pipeline-security.md). **This is exactly the second-repo write credential V1 deliberately deferred** ([../../packaging/homebrew/README.md](../../packaging/homebrew/README.md)).

## Synergy with Sparkle (0009)

[0009](0009_sparkle-auto-update.md) also extends `release.yml` (sign the update + publish the appcast). Same pattern: the tag fans out to every channel. The `CHANGELOG.md` section that becomes the GitHub Release body is also the natural source for the Sparkle appcast `<description>`. **Build the "extract the `[x.y.z]` section" helper once and reuse it** for release notes and the appcast.

## Acceptance criteria

1. `git tag vX.Y.Z && git push` publishes the DMG + checksum, sets the GitHub Release body to the `CHANGELOG.md` `[x.y.z]` section, and updates the tap's cask (`version` + `sha256`) — with no manual steps.
2. A tag with no matching `CHANGELOG.md` section fails the release before any artifact is published.
3. `brew upgrade` picks up the new version from the tap, and the cask's `sha256` matches the published checksum.
4. The cross-repo token is fine-grained, scoped to `homebrew-freeflow` `contents:write` only.
5. `packaging/homebrew/freeflow.rb` remains the reviewed source of the cask's shape; only `version`/`sha256` are generated.

## Related

- [../architecture/release-pipeline.md](../architecture/release-pipeline.md) — the workflow this extends
- [../../packaging/homebrew/README.md](../../packaging/homebrew/README.md) — the manual cask process this automates
- [0005_release-pipeline-security.md](0005_release-pipeline-security.md) — credential-handling principles for the new token
- [0009_sparkle-auto-update.md](0009_sparkle-auto-update.md) — the appcast extension that shares this release-fan-out pattern
- [../conventions/versioning-and-releases.md](../conventions/versioning-and-releases.md) — the tag-driven release protocol
