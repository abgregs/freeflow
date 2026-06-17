# Conventions: Git

## Branches

- **`main`** is always green and always installable. Protected — no direct pushes.
- **Feature branches** off `main`: `feat/<short-description>`, `fix/<short-description>`, `docs/<short-description>`.
- **Stacked branches** allowed when work naturally chains: `feat/foo-step-2` branches off `feat/foo-step-1`. Both target `main`; rebase the dependent after the parent merges.

## Commits

Conventional Commits. The first line is `type(scope): subject` under 72 characters.

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `perf`, `style`.

Scopes are loose but should reflect the area changed: `hotkey`, `audio`, `build`, `permissions`, `settings`, `agents` (for AGENTS.md and agent config), etc.

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

- Only PR merges, via **merge commit** — each PR lands as an explicit `Merge pull request #N` commit with the branch's conventional commits preserved beneath it. **Why:** replaces the rebase-merge convention previously recorded here — PRs #2 and #3 merged with merge commits, and the merge bubble keeps PR boundaries visible in history; the doc now matches actual practice.
- Hotfixes follow the same PR flow, just on a `hotfix/` branch.
- `main` is protected by a repository **ruleset** (not classic branch protection): a PR is required to land changes, force-pushes and branch deletion are blocked, and merging requires **code-owner review** — the maintainer's approval, via [`.github/CODEOWNERS`](../../.github/CODEOWNERS) (`* @abgregs`). The maintainer is the only account with write access, so they are also the only one who can press merge; fork contributors can open PRs but cannot merge them. **Why admin bypass exists:** GitHub forbids approving your own PR, so the repository-admin role is a ruleset bypass actor — without it the maintainer's own PRs would deadlock against the code-owner requirement. The bypass only affects the maintainer's own actions; external PRs are still gated on the maintainer's approval.
- Release tags (`v*`) are protected by a separate ruleset: deletion and force-push are blocked (no bypass), keeping released tags immutable per [../planning/0005_release-pipeline-security.md](../planning/0005_release-pipeline-security.md). Creation stays open so releases can be tagged.

## Tags and releases

- Releases are tagged `vMAJOR.MINOR.PATCH` from `main`; pushing the tag triggers [`.github/workflows/release.yml`](../../.github/workflows/release.yml), which builds, signs, notarizes, and publishes. `v*` tags are immutable (protected — see above).
- Versioning rules, pre-release tags, the two macOS version fields, and per-channel update behavior live in [versioning-and-releases.md](versioning-and-releases.md); pipeline setup is the [release-pipeline runbook](../architecture/release-pipeline.md).

## Related

- [../planning/_index.md](../planning/_index.md) — open items including release automation
- [anti-patterns.md](anti-patterns.md) — git anti-patterns specifically
