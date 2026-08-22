# Conventions: Git

## Branches

- **`main`** is always green and always installable. Protected — no direct pushes.
- **Feature branches** off `main`: `feat/<short-description>`, `fix/<short-description>`, `docs/<short-description>`.
- The `docs/doc-sync-*` prefix is reserved for the automated doc-sync routine's branches ([doc-maintenance.md](doc-maintenance.md)).
- **Stacked branches** allowed when work naturally chains: `feat/foo-step-2` branches off `feat/foo-step-1`. At creation each targets its **parent**; a child retargets to `main` only after its parent merges (see the stacked-PR rules under Pull requests). **Why:** replaces the "both target main" wording that contradicted the PR-section convention — targeting the parent at creation is what keeps a stacked PR's diff reviewable as just its own changes.

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

No emoji. No co-author trailers from tools. No `chore: misc updates` style commits. No empty commits — sole exception: the doc-sync run-record commit ([doc-maintenance.md](doc-maintenance.md)).

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

- Stacked PRs target their parent branch, not `main`. After merging the parent PR, **explicitly retarget the child while it is open**: `gh pr edit <n> --base main`. Do **not** delete the parent branch to trigger auto-retargeting — in practice GitHub *auto-closed* the child instead (PR #23, 2026-07-08, after the parent branch was deleted post-merge; recovery required recreating the ref, reopening, then retargeting — in that order). Delete stack branches only at the very end, after every child targets `main`. **Why:** replaces the earlier delete-to-retarget advice recorded here, which replaced the merge-alone-retargets claim before it (PR #17 landed on its still-existing parent and was re-landed as #18); explicit retarget is the only variant that has not misfired.

## Maintainer-only git operations (agents: read this first)

Merges are the maintainer's personal sign-off points and are **never run by agents or automation — no exceptions, including when a skill or workflow instructs otherwise**:

- `git merge` — any form, **including merging `main` (or a parent branch) into a feature branch** to refresh it
- `gh pr merge`

Pushing is **not** restricted: agents push feature branches (new branches and stacked-PR branches included) and open/edit PRs against any base. What protects `main` is not agent discipline but the repository's "Protect main branch" ruleset on GitHub: every change to `main` arrives via pull request, force-pushes and deletion are blocked, and the maintainer's bypass applies to PR merges only — a direct `git push origin main` is rejected server-side for everyone, maintainer included.

Agents do everything up to the merge — stage, commit, push, write PR bodies, `gh pr create`/`gh pr edit`, retarget bases — then stop and hand the maintainer the exact single-line merge command, and continue once it has been executed. Merge commands are also deny-listed in the repo's `.claude/settings.local.json`. **Why:** every history join on `main` passes through the maintainer's hands by design — the ruleset is the wall against pushes, the deny-list plus this section against merges.

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
