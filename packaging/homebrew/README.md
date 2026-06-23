# Homebrew cask

Free Flow is distributed through a **Homebrew tap** — a separate GitHub repo,
`abgregs/homebrew-freeflow`, that Homebrew discovers by name. This folder holds
the **source-of-truth template** (`freeflow.rb`); the live cask lives in the tap
at `Casks/freeflow.rb`.

## Why a tap, not the official `homebrew-cask`

The core `homebrew-cask` repo has notability requirements and a review queue. A
personal tap has neither — you control it, updates are instant, and the only
extra step for users is naming the tap.

## Install (for users)

```bash
brew install --cask abgregs/freeflow/freeflow
# or
brew tap abgregs/freeflow && brew install --cask freeflow
```

## One-time tap setup

1. Create a public repo named exactly `homebrew-freeflow`.
2. Add `Casks/freeflow.rb` — copy this folder's `freeflow.rb`.

## Per release

After [`release.yml`](../../.github/workflows/release.yml) publishes a tagged
DMG and its `.sha256`:

1. Update `version` and `sha256` in `freeflow.rb` (the `sha256` is the value in
   the published `FreeFlow-x.y.z.dmg.sha256`). The `url` derives from `version`,
   so it needs no edit.
2. Copy the updated `freeflow.rb` to the tap repo's `Casks/freeflow.rb` and push.
3. Verify: `brew install --cask abgregs/freeflow/freeflow`.

This bump is manual for V1. Automating it (the release workflow opening a PR
against the tap repo via a cross-repo token) is a future enhancement — kept out
of V1 to avoid handling a second repo's write credential in CI.

## Related

- [../../docs/architecture/release-pipeline.md](../../docs/architecture/release-pipeline.md) — the pipeline that produces the DMG + checksum the cask points at
- [../../docs/architecture/distribution.md](../../docs/architecture/distribution.md) — the three distribution channels and signing identities
