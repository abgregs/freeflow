# Conventions: Git

## Branches

- **`main`** is always green and always installable. Protected — no direct pushes.
- **Feature branches** off `main`: `feat/<short-description>`, `fix/<short-description>`, `docs/<short-description>`.
- **Stacked branches** allowed when work naturally chains: `feat/foo-step-2` branches off `feat/foo-step-1`. Both target `main`; rebase the dependent after the parent merges.

## Commits

Conventional Commits. The first line is `type(scope): subject` under 72 characters.

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `perf`, `style`.

Scopes are loose but should reflect the area changed: `hotkey`, `audio`, `build`, `permissions`, `settings`, `claude` (for CLAUDE.md), etc.

Body uses dashes for bullets. Wrap at ~72 columns. Reference variables/functions/files in backticks. Include a `**Why:**` line in the body for any commit that introduces a non-obvious tradeoff or replaces a previous convention.

Example:

```
fix(audio): wait for first buffer before stopping capture

- `AVAudioEngine.start()` returns synchronously but the input tap callback
  only fires once the engine has produced its first buffer (~60–100 ms)
- Short presses that end inside that window dropped the entire utterance
- Add a bounded wait (up to 300 ms) for at least one buffer before teardown
```

No emoji. No co-author trailers from tools. No `chore: misc updates` style commits.

## Pull requests

- Small. A PR that touches more than ~500 lines or more than ~8 files is probably two PRs.
- Title mirrors the lead commit's subject.
- Body uses this skeleton:

  ```
  ## Summary
  1-2 sentences.

  ## Scope
  Which files/areas are affected.

  ## Changes Made
  - Bulleted list.

  ## Impact
  Behavior change, perf, breaking changes, etc.

  ## Testing
  - [ ] Verification checklist.
  ```

- Stacked PRs target their parent branch, not `main`, until the parent merges. Then GitHub auto-retargets the child.

## When to commit

- Commit when a logical unit of work is complete and tests pass.
- Don't bundle unrelated changes. If a fix and a feature are in the same branch by accident, split them at commit time.
- Don't commit broken intermediate states. Use stash or worktrees for parking work.

## What touches `main`

- Only PR merges, via **rebase merge** — keeps `main`'s history linear with the branch's conventional commits preserved (the documented-in-`_index.md` decision was never written down; this records the convention the existing 46-commit linear history already follows).
- Hotfixes follow the same PR flow, just on a `hotfix/` branch.
- Direct push to `main` is permanently disabled in repo settings.

## Tags and releases

- Releases are tagged `vMAJOR.MINOR.PATCH` from `main`.
- A GitHub Action (TODO) reads the tag, builds the signed/notarized release, and attaches it.
- See [../architecture/distribution.md](../architecture/distribution.md) for the release pipeline.

## Related

- [../planning/_index.md](../planning/_index.md) — open items including release automation
- [anti-patterns.md](anti-patterns.md) — git anti-patterns specifically
