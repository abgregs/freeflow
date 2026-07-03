# Planning: Automated Doc Sync (roadmap 0015)

Free Flow's docs-first working convention is currently *delivered* through two project-scoped Claude Code skills — `brief` and `debrief` in `.claude/skills/` — copied from the maintainer's personal tooling and woven through the contributor guidance ([`AGENTS.md`](../../AGENTS.md), [`docs/_index.md`](../_index.md), [current-focus.md](current-focus.md), [milestones.md](milestones.md)). That delivery mechanism was a mistake, for two reasons:

- **Project-scoped skills are injected, not offered.** Everything in `.claude/skills/` rides into every Claude Code session in this repo as invokable skill metadata — the *model* can trigger a pre-task briefing or post-task doc review whether or not the human asked for one. The "optional tooling" framing in `docs/_index.md` is not honest for agent-assisted contributors, and it privileges one harness in a repo that claims harness-neutrality.
- **It puts a maintainer burden on every contributor.** The post-task doc review exists to keep `docs/` synced with the code — that is doc *maintenance*, a maintainer concern. A contributor should read the docs and write good code; keeping the docs honest shouldn't be their job.

This roadmap inverts the model. Contributor guidance becomes harness-neutral ("read the applicable docs before a non-trivial change; doc updates alongside a change are welcome, never required"), and doc/code drift is caught by an **automated, scheduled maintainer routine**: it reviews new commits on `main`, applies high-confidence doc updates behind an adversarial review pass, and opens a PR — ambiguous findings are flagged in the PR body instead of edited.

## Piece 1 — Retire the project-scoped skills

- Delete `.claude/skills/brief/` and `.claude/skills/debrief/` — the whole `.claude/skills/` directory; nothing else under `.claude/` is tracked.
- Rewrite every reference so guidance names *the docs*, not *a skill*:
  - `AGENTS.md` — the before/after-non-trivial-change paragraphs drop the skill links; "after" becomes "doc updates are welcome, not required — drift is caught by the maintainer's automated doc sync".
  - `docs/_index.md` — the working-convention paragraph, same change.
  - `current-focus.md` — the working agreement, the 0002 queue note, and the notes-for-the-agent item that route through `brief`/`debrief`.
  - `milestones.md` — the intro's `brief` mention.
  - `0006_runtime-security-hardening.md` — the "review the applicable conventions first" parenthetical.
- Planning records keep their history: this spec and its `_index.md`/`current-focus.md` entries still *name* the skills. The rewrite targets guidance — instructions a contributor is expected to follow — not the record of why the skills left.
- The maintainer's user-scoped copies of these skills are untouched — this removes the *project's* copy, not the tooling itself.

## Piece 2 — The doc-sync playbook lives in the repo

A new `docs/conventions/doc-maintenance.md` is the routine's spec; the routine's prompt stays a thin pointer at it. **Why in-repo:** the routine's behavior is reviewable and versioned like any other convention. It covers: the trigger and schedule; range semantics (the cursor branch below, half-open ranges, UTC dates); the review workflow — the old `debrief` flow, adapted from "the change I just made" to "the commits since the last run"; the confidence rubric; the adversarial pass; the PR format and lifecycle (flag carry-forward, closed-PR semantics); and failure behavior (abort loudly, never guess a range). `conventions/` already holds process docs (`git.md`), so no new docs category is needed. `git.md` gains one line reserving the `docs/doc-sync-*` branch prefix for the routine.

## Piece 3 — The scheduled routine

A **GitHub Actions workflow** (`.github/workflows/doc-sync.yml`) runs the routine via `anthropics/claude-code-action` on a cron schedule — 13:00 UTC on the 1st and 15th of each month, matched to the repo's actual commit cadence — plus a `workflow_dispatch` trigger for manual runs. **Why Actions over a Claude Code cloud routine** (reversing this spec's earlier draft): a cloud session's GitHub credential can reach every repository the connecting account sees — App installation scope is not session-level access control — while a workflow's ephemeral `GITHUB_TOKEN` is structurally scoped to this repo alone; the schedule and prompt are versioned in-repo instead of in an external console; and runner minutes are free on a public repo. The trade-offs: an `ANTHROPIC_API_KEY` repository secret (metered API billing — keyed to a dedicated Console workspace with a monthly spend limit; roughly $2–4/month at this cadence), and the workflow joins the [0005](0005_release-pipeline-security.md) hardening surface (SHA-pinned actions, least-privilege `permissions:` — the pattern `release.yml` already follows).

**State is a git ref, not prose.** The branch `doc-sync/cursor` points at the last commit a completed run covered. Every run reviews the half-open range `doc-sync/cursor..origin/main` (head snapshotted at run start) and fast-forwards the cursor to that head when it completes — clean runs advance it too, so a quiet stretch is never re-reviewed, and a crashed run doesn't advance it at all. `main` is append-only (force-push blocked), so the fast-forward never needs force. Bootstrap is explicit: when this roadmap's implementation PR merges, the maintainer creates the branch at that merge commit. A missing cursor, or one that is not an ancestor of `origin/main`, aborts the run loudly — the routine never guesses a range.

Each run:

1. **Exit early** if the range is empty, or if a doc-sync PR is still open (identified by its `doc-sync` label and author, not branch name alone) — the cursor stays put, so the pending commits are covered next time.
2. **Review.** Read the range's diff and commit messages, navigate `docs/_index.md` to the docs covering the changed areas, and classify each drift finding per the confidence rubric below.
3. **Adversarial pass.** Every proposed edit is independently re-verified against the rubric before it is applied, with the burden of proof on the edit: deliberate intent must be evidenced — a `**Why:**` commit-body line, a PR-body statement, a planning doc — not inferred from having merged, since every commit here arrives via a self-merged PR. Edits that fail or are uncertain demote to flags; an edit substantially identical to one in a previously closed doc-sync PR is flagged, not re-proposed.
4. **Land.** Edits or flags → one `docs/doc-sync-<UTC date>` branch (plus a short unique suffix, so a same-day retry can't collide; a rejected push aborts the run rather than force-pushing) and one PR on the [git.md](../conventions/git.md) skeleton, with a **Flagged for maintainer** checklist and a `Covers:` line for review context. A flags-only run carries one allow-empty `docs:` run-record commit so the PR can exist — a deliberate, documented exception to `git.md`'s no-content-free-commits norm. Nothing to say → no PR; just advance the cursor.

**PR lifecycle.** Merging accepts the edits; closing rejects them — for partial acceptance, edit the branch before merging rather than closing. Unchecked flags from the previous PR carry forward into the next PR's checklist until the maintainer checks them off or the drift is gone — a close never buries a flag, and rejected edits are remembered (step 3) instead of re-proposed on every run.

**Credential.** The workflow authenticates to GitHub with its ephemeral, job-scoped `GITHUB_TOKEN` (`contents`, `pull-requests`, and `issues` write — the last for the `doc-sync` label) — no PAT, no standing credential. Three consequences on record: events created with `GITHUB_TOKEN` cannot trigger other workflows (GitHub's recursion guard), so even a rogue `v*` tag push could not fire the signing release workflow — the release-adjacency concern is closed **by construction**, not policy. The same guard means doc-sync PRs won't trigger PR-based CI: when [0014](0014_test-coverage-and-ci.md)'s required check lands, PR creation must move to a differently-authenticated token (e.g. the Claude GitHub App's) or the check must be dispatched manually — a known interaction to resolve when 0014 is picked up. And doc-sync PRs are authored by `github-actions[bot]`, so the maintainer satisfies the code-owner review requirement with an ordinary approval — no admin bypass needed. Claude itself is billed via the `ANTHROPIC_API_KEY` secret.

## The confidence rubric

- **Edit directly** (still lands behind the adversarial pass and PR review): a convention or behavior deliberately and *completely* replaced, with the docs now contradicting the code; references to renamed or removed symbols, files, or settings; landed work whose planning status is stale (`current-focus.md`, `_index.md` markers).
- **Flag, never edit:** partial migrations (both patterns coexist — surface the conflict, don't average it), and drift against the docs-authoritative set, where code drifting from the docs is a suspected regression to report, never a doc update. That set is enumerated by location, not adjective: `AGENTS.md`'s numbered load-bearing rules, everything under `docs/decisions/`, [threading-invariant.md](../architecture/threading-invariant.md), and [anti-patterns.md](../conventions/anti-patterns.md); everywhere else, merged code is the source of truth and docs follow. Doubt about set membership is itself a flag. Doc deletions beyond line-level edits are flag-only.
- The routine never edits code.

## Non-goals

- No auto-merge — the maintainer reviews every doc-sync PR (the adversarial pass reduces review load; it doesn't replace it).
- No CI check or enforcement of doc freshness on contributor PRs — this roadmap *removes* contributor-side process, it doesn't add any.
- No change to the maintainer's personal user-scoped skills.
- 0013/0014 and the rest of the backlog are unaffected.

## Acceptance criteria

1. `.claude/skills/` is gone, `git grep '.claude/skills' -- ':!docs/planning'` returns nothing, and no guidance doc (`AGENTS.md`, `docs/_index.md`, `current-focus.md`, `milestones.md`) instructs use of the skills. Planning records keep their historical mentions.
2. Contributor guidance is harness-neutral: docs-first before a change, doc updates welcome-not-required after, the automated sync noted.
3. `docs/conventions/doc-maintenance.md` exists, is indexed, and covers trigger, range semantics, review workflow, rubric, adversarial pass, PR format and lifecycle, and failure behavior — under ~150 lines. `git.md` reserves the `docs/doc-sync-*` prefix.
4. The workflow exists with the `ANTHROPIC_API_KEY` secret configured, its `GITHUB_TOKEN` can push a branch and open a PR, and `doc-sync/cursor` sits at the implementation PR's merge commit. The first manually dispatched run is pointed at a historical base with known drift, so the full path — review, rubric, adversarial pass, PR with `Covers:` line and flag checklist — is exercised end to end; a no-op run does not satisfy this criterion.
5. Doc health passes: every index updated, no dead links left by the skill deletion.

## Related

- [`AGENTS.md`](../../AGENTS.md) — the load-bearing rules the routine must treat as authoritative
- [../conventions/git.md](../conventions/git.md) — branch naming, commit format, and the PR skeleton the routine follows; gains the reserved-prefix note
- [../_index.md](../_index.md) — the working-convention paragraph Piece 1 rewrites
- [current-focus.md](current-focus.md) — the working agreement Piece 1 rewrites
- [0005_release-pipeline-security.md](0005_release-pipeline-security.md) — the trust boundary the routine's credential joins
