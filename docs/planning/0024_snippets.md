# Planning: Snippets (roadmap 0024)

A queued backlog item, fresh idea 2026-07-06. **Snippets** are spoken
shorthand: the user saves a phrase and a replacement, and when the phrase
appears in a transcription it is replaced with the saved text before
insertion — "email me" → "You can contact me at me@example.com",
"my linkedin profile" → the full URL, "got questions" → "Does that make
sense? Let me know if you have any questions." The payoff is dictating
things voice is bad at (links, email addresses, boilerplate sign-offs)
via short, easy-to-say triggers.

**Posture check against [0008](0008_custom-dictionary-redesign.md)'s drop
decision.** The on-record posture — off-the-shelf models as-is, no
dictionary/glossary/role-pack/personalization layers — covers layers that
shape *recognition* (prompt biasing, vocabulary conditioning). Snippets
touch none of that: no prompt, no `DecodingOptions`, no model behavior —
a deterministic, user-authored find/replace over the *finished*
transcript. Mechanically it is 0008's dropped Tier 2, repurposed from
correction ("fix what the model spelled") to expansion ("say less, paste
more") — a productivity feature, not a quality layer. The prompt-echo
failure class is structurally absent: every replacement is verbatim text
the user authored, so the pass cannot invent words.

## Design

1. **Pure expander.** A static pure function (e.g. `SnippetExpander.apply
   (_:to:)`): case-insensitive, word-boundary phrase matching; tolerant of
   trailing punctuation the model appends ("got questions." still
   matches); longest-phrase-first precedence on overlap; **single pass —
   replaced output is never re-scanned**, so recursive/chained expansion
   is impossible by construction. No model in the loop; unit-testable like
   `convert` and the 0023 trim helper.
2. **Pipeline placement.** Applied in `FreeFlowSession.handleDeactivate`
   to the string `transcribe` returns, before `insertText`. The expanded
   string is what [0019](0019_last-transcript-recovery.md) keeps — the
   recovered transcript must equal what was inserted.
3. **Storage.** A single `Settings.snippets` key (one `SettingKey`
   declaration, anti-pattern #8) holding an ordered list of
   (phrase, replacement) pairs — a user-facing setting, so `SettingsStore`
   from day 1 (load-bearing rule #5). `@AppStorage` can't represent pairs,
   so the Settings UI binds through a small `@Observable` model via the
   typed store — the pattern the removed `DictionaryModel` established.
4. **Settings UI.** A "Snippets" section: rows of phrase → replacement
   with add/delete, the same shape as the removed Custom Dictionary
   section but with two fields per row.
5. **Session wiring.** The session subscribes via
   `store.publisher(for: Settings.snippets)`. This re-adds a
   settings-to-cycle feed like the one 0008's removal deleted — but that
   removal was load-bearing because the consumer was model conditioning;
   here the consumer is a pure post-processor and the echo mechanism does
   not exist.

## Known limitations (on record, not blockers)

- **Triggers fire on any natural utterance.** Saying "email me the file"
  expands too. Mitigation is user-side — pick distinctive trigger
  phrases; no spoken command grammar in v1.
- **Matching is against what the model transcribed.** A trigger that
  transcribes unreliably won't fire; fixing recognition is exactly the
  dropped-0008 territory this feature stays out of.
- **Punctuation seams.** Replacement ending "." where the transcript had
  "got questions." risks doubled terminal punctuation — decide the dedupe
  rule at implementation time, with a test.

## Acceptance criteria

1. The expander is pure and unit-tested: case handling, word boundaries
   (no mid-word matches), multi-word phrases, trailing-punctuation
   tolerance, overlap precedence, no recursive expansion, and non-ASCII/
   emoji replacements surviving the grapheme-safe keystroke chunking
   ([0011](0011_keystroke-injection.md)).
2. An empty snippet list is a byte-identical pass-through — zero behavior
   change when the feature is unused.
3. One `Settings.snippets` `SettingKey`; no inline `UserDefaults`
   literals; `swift test` green.
4. Session-level test: a cycle with a snippet configured inserts the
   expanded text; with 0019 landed, the recovered transcript equals the
   inserted string.
5. Nothing in the prompt/decode path changes; docs and README describe
   snippets as text expansion, never as a dictionary or vocabulary
   feature.

## Related

- [0008_custom-dictionary-redesign.md](0008_custom-dictionary-redesign.md) — the dropped redesign: mechanism precedent (Tier 2 find/replace) and the recognition-layer posture this spec must not re-enter
- [0019_last-transcript-recovery.md](0019_last-transcript-recovery.md) — recovery keeps the post-expansion string
- [0011_keystroke-injection.md](0011_keystroke-injection.md) — the insertion path replacements flow through
- [../architecture/settings-store.md](../architecture/settings-store.md) — the typed-key/publisher pattern the storage follows
