# Requirement: Custom Dictionary

The user can add terms to a custom dictionary that biases WhisperKit toward recognizing those words. Useful for proper nouns, technical jargon, and personal names that Whisper's general model tends to mishear.

## User flow

1. Settings → "Custom Dictionary" section.
2. A list of current terms with a delete button per row.
3. A text field + Add button to insert a new term.
4. Terms persist immediately on add/delete.

## Storage

`UserDefaults.standard` under key `customDictionaryTerms` as `[String]`. Default: empty as of M6 (`TranscriptionService.customDictionaryTerms = []`); the Settings UI to edit the list lands in M8, at which point a curated starter list can also be declared in `Constants.defaultDictionaryTerms`.

## How it reaches WhisperKit

`TranscriptionService.buildDecodingOptions()`:

1. Reads the array from `UserDefaults`.
2. Joins with `", "` into a single prompt string (with a leading space).
3. Tokenizes via the WhisperKit tokenizer.
4. **Filters out any tokens >= `tokenizer.specialTokens.specialTokenBegin`** before passing to `DecodingOptions(promptTokens:)`.

The filter step is mandatory. **Why:** special tokens (timestamp markers, language tags, etc.) injected into the prompt corrupt decoding — silently. The output looks like noise. This is documented in [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) and any change to the prompt-building logic must preserve this filter.

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
