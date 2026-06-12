# Planning: Custom Dictionary Redesign (roadmap 0008)

The V1 custom dictionary (prompt-token biasing, M8) is **cut from the public
launch** and redesigned here. Decision made 2026-06-12 after a field bug and a
feasibility review of the "bigger glossary" direction.

## Why V1 ships without it

1. **Prompt echo corrupts output.** Field bug: dictations randomly end with a
   dictionary term ("…Vite") the user never spoke. Mechanism: dictionary terms
   are fed to Whisper as conditioning context; on weak audio evidence —
   typically the trailing silence/breath after the last word — the decoder
   falls back on the conditioning and emits prompt content. The hallucinated
   segment is appended last, so the term lands at the very end. The
   empty-result fallback never fires because "real sentence + Vite" is
   non-empty. Pasting words the user never said is the worst failure this app
   can produce.
2. **A hard ceiling blocks the roadmap.** Whisper's conditioning budget is 224
   tokens (WhisperKit `maxTokenContext`), and WhisperKit does not truncate —
   oversized prompts silently degrade decoding. Role-pack-scale glossaries
   (100+ terms) are not feasible through this mechanism, ever.
3. **No guardrails, thin validation.** The Settings UI accepts unlimited terms
   with no budget feedback; biasing is case-sensitive and literal; the A/B
   harness has validated exactly one term on one clip.

## What the removal task touches (small, pre-launch)

- Remove the Custom Dictionary section from `SettingsView` (and
  `DictionaryModel` if nothing else uses it).
- **Keep**: the `customDictionaryTerms` `SettingKey` (reserve the key name),
  `TranscriptionService.customDictionaryTerms` + `buildPromptTokens` +
  `filterSpecialTokens` and their tests (the plumbing is sound and tested),
  the empty-prompt fallback, and the `small.en` default (it is also simply
  more accurate — that rationale stands on its own).
- Update [../requirements/custom-dictionary.md](../requirements/custom-dictionary.md)
  to "deferred — redesigned in 0008", the README features table/bullets, and
  `current-focus.md`.

## Redesign: two tiers

**Tier 1 — prompt biasing (small, budgeted).** Today's mechanism, kept for a
handful of high-value terms, with the guardrails it always needed: a token
budget meter against the 224-token ceiling, trailing-silence trimming before
decode, and `noSpeechThreshold` tuning to drop hallucination-prone segments.
**Why kept at all:** biasing can fix *recognition* ("Veed" → "Vite") — a
post-processor can only fix *spelling* of what was recognized.

**Tier 2 — deterministic post-processing correction (scales).** A
word-boundary find/replace pass over the finished transcription
("github" → "GitHub", "claude code" → "Claude Code"). Runs in microseconds,
handles arbitrarily large term lists, pure-unit-testable with no model in the
loop, and **structurally cannot invent words** — the prompt-echo failure mode
does not exist here.

**Role packs ride Tier 2.** Curated, versioned term lists by persona or app
context — web developer, Claude Code user, creative writing, email — shipped
as data, individually toggleable, merged with the user's own terms. Feasible
precisely because Tier 2 has no size ceiling; a user's few personal
high-priority terms may additionally opt into Tier 1 within the budget.

## Testing plan

- **Tier 2:** pure unit tests (case handling, word boundaries, multi-word
  terms, overlap precedence, idempotence). No model, no fixtures.
- **Tier 1:** extend the env-gated A/B harness (`DictionaryEvalTests`) from
  one clip/term to a small persona fixture set; add a regression fixture for
  prompt echo (clip with trailing silence + active prompt must not emit
  prompt terms).
- **Bug regression:** the prompt-echo symptom above is the canonical failure;
  any future Tier 1 work is gated on the echo fixture passing.

## Acceptance criteria

1. V1 ships with no dictionary UI; plumbing and tests remain; `swift test`
   stays green.
2. The redesigned feature lands as Tier 2 first (correction pass + role
   packs), Tier 1 only after the echo regression fixture exists and passes.
3. [../requirements/custom-dictionary.md](../requirements/custom-dictionary.md)
   and the README stay truthful at every step (no advertised feature that
   isn't shipped).

## Related

- [../requirements/custom-dictionary.md](../requirements/custom-dictionary.md) — the V1 feature this supersedes
- [../conventions/tests.md](../conventions/tests.md) — the A/B eval harness
- [0004_model-loading-indicator.md](0004_model-loading-indicator.md) — same M8 lineage of model-behavior follow-ups
