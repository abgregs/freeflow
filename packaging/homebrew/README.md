# Homebrew cask

River is distributed through a **Homebrew tap** — a separate GitHub repo,
`abgregs/homebrew-river`, that Homebrew discovers by name. This folder holds
the **source-of-truth template** (`river.rb`); the live cask lives in the tap
at `Casks/river.rb`.

## Why a tap, not the official `homebrew-cask`

The core `homebrew-cask` repo has notability requirements and a review queue. A
personal tap has neither — you control it, updates are instant, and the only
extra step for users is naming the tap.

## Install (for users)

```bash
brew install --cask abgregs/river/river
# or
brew tap abgregs/river && brew install --cask river
```

## One-time tap setup

1. Create a public repo named exactly `homebrew-river`.
2. Add `Casks/river.rb` — copy this folder's `river.rb`.

## Per release

Automated (planning 0013): after [`release.yml`](../../.github/workflows/release.yml)
publishes a tagged DMG and its `.sha256`, the same workflow renders this
template — substituting only `version` (from the tag) and `sha256` (read from
the published `River-x.y.z.dmg.sha256`) — and pushes the result to the tap's
`Casks/river.rb` using the `TAP_BUMP_TOKEN` secret (a fine-grained PAT with
`contents: write` on `abgregs/homebrew-river` only). Pre-release tags never
touch the tap.

The tap is therefore a **generated artifact**: the cask's shape (`name`, `desc`,
`depends_on`, `caveats`, `zap`, the `url` pattern) is reviewed here, in this
template, and never edited by hand in the tap. If the tap push step ever fails
(the release itself is already published at that point), the manual fallback is
the same substitution: copy this file across with the new `version`/`sha256`
and push.

Verify after a release: `brew install --cask abgregs/river/river`.

## Related

- [../../docs/architecture/release-pipeline.md](../../docs/architecture/release-pipeline.md) — the pipeline that produces the DMG + checksum the cask points at
- [../../docs/architecture/distribution.md](../../docs/architecture/distribution.md) — the three distribution channels and signing identities
