---
name: debrief
description: Post-task debrief for Free Flow. Reviews code changes against docs/, proposes doc updates for new patterns or replaced conventions, and runs a doc health check. Use after completing any non-trivial code task.
---

You have just completed a code task in Free Flow. Review the changes against the project documentation so the docs stay aligned with the code.

**Context:** $ARGUMENTS

## Workflow

1. **Understand what changed.** Run `git diff --stat` and `git diff` (or `--cached` for staged changes); summarize what was added, modified, and removed.
2. **Review against docs.** Navigate from `docs/_index.md` via the category `_index.md` files; read the docs covering the changed areas, plus the load-bearing rules in `AGENTS.md`. For each relevant doc: still accurate? still complete? still relevant?
3. **Propose updates.** List proposed doc changes grouped by file — updates, new files, and `_index.md` entries. If nothing needs updating, say so explicitly and explain why. Confirm with the user before editing.
4. **Execute.** Make the approved edits and update the relevant `_index.md`. Keep files under ~150 lines — split into focused sub-docs if an edit pushes one over.
5. **Health check.** Every file appears in its folder's `_index.md` (no orphans); every entry points at a real file (no dead links); every entry has a one-line summary; no docs contradict each other or reference renamed/removed code. Fix what you find, confirming non-trivial fixes with the user.
6. **Summarize.** Docs updated, docs created, health-check results, and any open items.

## Important

- Do NOT skip the review for "minor" changes — small changes can invalidate docs.
- Do NOT delete doc content without user confirmation.
- Prefer updating existing docs over creating new ones — new files only when the topic genuinely fits nowhere.
- When a milestone or notable change lands, record it in `docs/planning/current-focus.md`, matching its existing entry style.
