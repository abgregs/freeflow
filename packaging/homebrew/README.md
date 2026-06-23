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

After [`release.yml`](../../.github/workflows/release.yml) publishes a tagged
DMG and its `.sha256`:

1. Update `version` and `sha256` in `river.rb` (the `sha256` is the value in
   the published `River-x.y.z.dmg.sha256`). The `url` derives from `version`,
   so it needs no edit.
2. Copy the updated `river.rb` to the tap repo's `Casks/river.rb` and push.
3. Verify: `brew install --cask abgregs/river/river`.

This bump is manual for V1. Automating it (the release workflow opening a PR
against the tap repo via a cross-repo token) is a future enhancement — kept out
of V1 to avoid handling a second repo's write credential in CI.

## Related

- [../../docs/architecture/release-pipeline.md](../../docs/architecture/release-pipeline.md) — the pipeline that produces the DMG + checksum the cask points at
- [../../docs/architecture/distribution.md](../../docs/architecture/distribution.md) — the three distribution channels and signing identities
