---
name: brief
description: Pre-task briefing for Free Flow. Surfaces applicable conventions, architectural constraints, and requirements from docs/ before planning a code change. Use when starting any non-trivial code task.
---

You are preparing to execute a code task in Free Flow. Before writing any code, ground yourself in the project's documentation and align your plan with established conventions.

**Task:** $ARGUMENTS

## Where the docs live

`docs/_index.md` is the root map. Every folder has an `_index.md` with one-line summaries — use those to triage relevance without opening every file:

- `docs/conventions/` — how code is written (style, layout, logging, persistence, tests, git, anti-patterns)
- `docs/architecture/` — how the system is structured and why (the session, capabilities, settings, threading invariant, distribution)
- `docs/requirements/` — what the product must do (core feature, activation modes, custom dictionary, limitations)
- `docs/planning/` — active and future work; `current-focus.md` is the status log
- `docs/decisions/` — ADRs; read before re-suggesting a known-deferred refactor

`AGENTS.md` carries the load-bearing rules that must not regress — always check them against the task.

## Workflow

1. **Discover.** Read `docs/_index.md`, then the category `_index.md` files; open the docs relevant to the task and follow their cross-references. Read `docs/planning/current-focus.md` for in-flight context.
2. **List applicable rules.** Group every applicable convention, constraint, and requirement by source file so the user can verify them.
3. **Check whether docs need updating first.** Does the task introduce a new pattern, contradict an existing convention, or hit a doc gap that would leave the plan unguided? Propose those doc changes (with user confirmation) before planning.
4. **Propose an aligned plan** (plan mode). Reference the conventions it follows; call out ambiguities and any conflicts between conventions.
5. **Note gaps** that don't block this task — they become candidates for the post-task `/debrief`.
6. **Ask, don't guess.** If a convention is ambiguous, ask before proceeding. Wait for plan approval before writing code.

## Important

- Do NOT skip doc discovery even if you think you know the codebase.
- Do NOT write code during this workflow — this is planning only.
