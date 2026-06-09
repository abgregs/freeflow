# Requirement: Custom Dictionary

The user can add terms to a custom dictionary that biases WhisperKit toward recognizing those words. Useful for proper nouns, technical jargon, and personal names that Whisper's general model tends to mishear.

## User flow

1. Settings → "Custom Dictionary" section.
2. A list of current terms with a delete button per row.
3. A text field + Add button to insert a new term.
4. Terms persist immediately on add/delete.

## Storage

`UserDefaults.standard` under key `customDictionaryTerms` as `[String]` (default `Constants.defaultDictionaryTerms`, empty). The Settings UI shipped in M8 — a per-row list with a delete button and an add field, bound through the typed `SettingsStore` because `@AppStorage` can't bind `[String]` (see [../architecture/settings-store.md](../architecture/settings-store.md)). `AppDelegate` forwards changes to `TranscriptionService.setCustomDictionaryTerms`; a curated starter list could later be declared in `Constants.defaultDictionaryTerms`.

## How it reaches WhisperKit

`TranscriptionService.buildPromptTokens(using:)`, called by `transcribe`:

1. Reads the current `customDictionaryTerms`.
2. Joins with `", "` into a single prompt string (with a leading space).
3. Tokenizes via the WhisperKit tokenizer.
4. **Filters out any tokens >= `tokenizer.specialTokens.specialTokenBegin`** before the result is passed as `DecodingOptions.promptTokens`.

The tokenizer only exists once the model is **loaded** (not merely downloaded). `loadModel()` uses `WhisperKit(model:, load: true)` so the tokenizer is ready before the first transcription — without it `buildPromptTokens` reads a nil tokenizer and silently builds an empty prompt.

The filter step is mandatory. **Why:** special tokens (timestamp markers, language tags, etc.) injected into the prompt corrupt decoding — silently. The output looks like noise. This is documented in [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) and any change to the prompt-building logic must preserve this filter.

## Model size matters

Prompt-token biasing is **unreliable on small models**. `base.en` frequently degenerates to **empty output** when given a prompt (the decode confidence collapses and WhisperKit drops the segment), which makes the dictionary inert. `small.en` — the default, see [../architecture/configuration.md](../architecture/configuration.md) — handles prompts robustly, so the custom dictionary effectively **requires `small.en` or larger**. This was established with the A/B eval harness ([../conventions/tests.md](../conventions/tests.md)).

Because a prompt can still occasionally empty a decode, `transcribe` **falls back to an unprompted run** when a prompted decode returns empty. The dictionary can therefore only ever *help* — it never turns a working dictation into an error or a silent no-op with lost audio.

## Choosing good terms

Enter the **hard word or name** you want spelled correctly (`Vite`, `Kubernetes`, `Siobhán`), not a transcription of a sentence you'll speak. WhisperKit treats the prompt as *text already transcribed*, so a term that echoes your whole utterance (e.g. `deploy vite` while saying "deploy vite") makes the model conclude there's nothing new → empty → fallback → no benefit. Multi-word terms are fine (`Visual Studio Code`); just don't make a term your sentence. Keep the list to words you actually dictate — an irrelevant term can mildly degrade output.

## Limits

- No explicit cap on number of terms, but very long prompts crowd out actual decoding capacity. Whisper's prompt is limited to roughly 224 tokens; a few dozen short terms is the sweet spot.
- Terms are case-sensitive as the tokenizer sees them; "GitHub" and "github" are different prompts.
- No fuzzy matching — the prompt is literal.

## Non-features

- No import/export of dictionaries (yet — see planning).
- No per-app dictionaries.
- No shared/synced dictionaries across devices.

## Related

- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — where the dictionary fits in the transcription step
- [../conventions/persistence.md](../conventions/persistence.md) — how the `customDictionaryTerms` key is stored
- [../architecture/configuration.md](../architecture/configuration.md) — the `small.en` default the dictionary depends on
- [../conventions/tests.md](../conventions/tests.md) — the A/B eval harness that verifies dictionary biasing
