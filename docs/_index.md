# Free Flow Docs

A macOS menu bar dictation app. Hold (or tap) a configurable activation key → capture mic audio → transcribe locally with WhisperKit → type at cursor. Apple Silicon, macOS 14+.

These docs are the source of truth for how Free Flow is built and maintained. The working convention: before a non-trivial change, surface the applicable conventions from these docs; afterwards, check them for staleness. The repo's `brief` and `debrief` skills (`.claude/skills/`) automate both for Claude Code users, but they are optional tooling — contributing requires no particular agent, harness, or skill. Doc updates alongside a change are welcome, not a requirement; the maintainer audits doc health and syncs as needed.

## Map

### [conventions/](conventions/_index.md)
How code is written: language style, file layout, naming, logging, persistence, tests, git, anti-patterns.

### [architecture/](architecture/_index.md)
How the system is structured and why: process model, the dictation pipeline, the event-tap threading invariant, permissions, configuration, distribution.

### [requirements/](requirements/_index.md)
What the product is supposed to do: the core feature spec, the activation-key/mode design, supported keys, accepted limitations.

### [planning/](planning/_index.md)
Active and future work: the walking-skeleton milestone, milestone roadmap, current focus.

### [decisions/](decisions/_index.md)
ADRs — load-bearing architectural decisions and the rationale for *not* taking specific refactors. Read before re-suggesting a known-deferred change.

## Conventions of these docs

- Files are kebab-case, single-topic, max ~150 lines.
- Every folder has an `_index.md` listing every file with a one-line summary.
- Rules carry a `**Why:**` annotation when the rationale isn't obvious or when the rule replaces a previous convention.
- Docs cross-link freely: a convention links to the architecture it depends on; a requirement links to the conventions that govern its implementation.

If something is missing or stale, it's a doc bug — fix it (or open a planning TODO).
