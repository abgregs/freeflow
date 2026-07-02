# Conventions: Doc Maintenance

`docs/` is kept in sync with the code by an automated, scheduled maintainer routine — the doc-sync routine — not by contributors. This file is the routine's spec: the routine's prompt is a thin pointer here, so editing this file changes the routine's behavior. Design rationale and decision history: [../planning/0015_automated-doc-sync.md](../planning/0015_automated-doc-sync.md).

## Trigger and schedule

- A GitHub Actions workflow ([.github/workflows/doc-sync.yml](../../.github/workflows/doc-sync.yml)) runs the routine via `anthropics/claude-code-action` on a cron schedule — 13:00 UTC on the 1st and 15th of each month. GitHub auth is the job's repo-scoped `GITHUB_TOKEN`; Claude auth is the `ANTHROPIC_API_KEY` repository secret (credential rationale: [0015](../planning/0015_automated-doc-sync.md)).
- Manual runs: trigger the workflow's `workflow_dispatch`, optionally passing an explicit historical base for testing the pipeline against known drift. A base-override run must **not** advance the cursor.
- GitHub auto-disables cron workflows after 60 days without repository activity; re-enable from the Actions tab if notified.

## Range semantics

- **State is the git branch `doc-sync/cursor`** — its tip is the last commit a completed run covered. PR-body `Covers:` lines are informational only.
- Each run reviews the half-open range `doc-sync/cursor..origin/main`, where the head is `origin/main`'s SHA snapshotted at run start; commits landing mid-run wait for the next run.
- On successful completion — including a clean, nothing-to-report run — fast-forward the cursor to that head. `main` is append-only (force-push blocked), so the fast-forward never needs force. A failed or aborted run leaves the cursor untouched.
- Bootstrap: the maintainer creates `doc-sync/cursor` (at the merge commit of 0015's implementation PR) and the `doc-sync` PR label once. The routine never creates either itself.
- All dates (branch names, run records) are UTC.

## A run, start to finish

1. **Exit early**, without advancing the cursor, if:
   - `doc-sync/cursor` is missing or is not an ancestor of `origin/main` → abort loudly; never guess a range;
   - the range is empty → nothing to do;
   - a doc-sync PR is still open — identified by the `doc-sync` label and the routine's author identity, never by branch name alone → the pending commits are covered next run.
2. **Review.** Read the range's diff and commit messages (and the PR bodies its merge commits reference, via `gh`). Navigate from `docs/_index.md` through the category `_index.md` files to the docs covering the changed areas. For each relevant doc: still accurate? still complete? Classify every drift finding per the confidence rubric into a proposed edit or a flag.
3. **Adversarial pass.** Independently re-verify every proposed edit against the rubric before applying it, with the burden of proof on the edit. Deliberate intent must be evidenced — a `**Why:**` line in a commit body, an explicit PR-body statement, or a planning doc; "it merged" proves nothing, since every commit on `main` arrives via a self-merged PR. Check closed doc-sync PRs: an edit substantially identical to one the maintainer closed is demoted to a flag citing that PR. Edits that fail the pass or are uncertain demote to flags.
4. **Land.** Apply surviving edits on a fresh branch (naming below) as conventional `docs:` commits per [git.md](git.md), updating the relevant `_index.md` files and keeping every touched doc under ~150 lines. A rejected push (branch already exists) aborts the run — never force-push. Edits or flags present → open one PR; neither → no PR. Either way the run is complete — fast-forward the cursor per Range semantics.

## The confidence rubric

- **Edit** (still gated by the adversarial pass and the maintainer's PR review):
  - a convention or behavior deliberately and *completely* replaced, with the docs now contradicting the code;
  - references to renamed or removed symbols, files, or settings;
  - landed work whose planning status is stale (`current-focus.md`, `_index.md` markers).
- **Flag, never edit:**
  - partial migrations — both patterns coexist; surface the conflict, don't average it;
  - drift against the docs-authoritative set below — code drifting from those docs is a suspected regression to report, never a doc update;
  - doc deletions beyond line-level edits;
  - anything whose intent cannot be evidenced.
- **The docs-authoritative set**, enumerated by location, not adjective: `AGENTS.md`'s numbered load-bearing rules; everything under `docs/decisions/`; [../architecture/threading-invariant.md](../architecture/threading-invariant.md); [anti-patterns.md](anti-patterns.md). Everywhere else, merged code is the source of truth and the docs follow it. Doubt about whether something belongs to the set is itself a flag.
- The routine never edits code, never force-pushes, never creates tags, and never merges or approves its own PRs.

## PR format and lifecycle

- Branch: `docs/doc-sync-<UTC date>-<short unique suffix>` (the suffix keeps a same-day retry from colliding). Label: `doc-sync`. Title mirrors the lead commit. Body: the [git.md](git.md) PR skeleton, plus:
  - `Covers: <base>..<head>` — the reviewed range, for context;
  - **Flagged for maintainer** — a `- [ ]` checklist: each flag with its evidence (the commits, the docs, the contradiction). Unchecked flags from the most recent prior doc-sync PR — merged or closed — carry forward until checked off or moot. Carried-forward flags attach to the next PR that opens; they do not themselves trigger one.
- A flags-only run has no doc edits, so the branch carries one allow-empty `docs:` run-record commit. **Why:** GitHub refuses a PR with no commits; this is the documented exception to git.md's no-content-free-commits norm.
- Merging accepts the edits. Closing rejects them — a later run that re-derives a rejected edit flags it instead of re-proposing. For partial acceptance, edit the branch before merging rather than closing.

## Failure behavior

- Abort loudly and cleanly on anything unexpected — a missing or diverged cursor, a rejected push, a `gh` failure. An aborted run leaves no branch, no PR, and an unmoved cursor, and exits nonzero so it surfaces as a failed workflow run.
- Never widen scope to "fix" the repo: no code edits, no tag pushes, no merges, no cleanup of unrelated branches.

## Related

- [../planning/0015_automated-doc-sync.md](../planning/0015_automated-doc-sync.md) — why this exists; credential scope and the decisions behind the design
- [git.md](git.md) — branch naming (the reserved `docs/doc-sync-*` prefix), commit format, and the PR skeleton
- [anti-patterns.md](anti-patterns.md) + [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — two members of the docs-authoritative set
