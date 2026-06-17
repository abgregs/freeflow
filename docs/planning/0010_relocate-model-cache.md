# Planning: Relocate the Model Cache out of ~/Documents (roadmap 0010)

WhisperKit's default download location is `~/Documents/huggingface`. Because the app is unsandboxed, the first time it writes there macOS shows a **"FreeFlow wants to access files in your Documents folder"** TCC prompt — confusing for a dictation app — and it leaves a `huggingface` folder cluttering the user's Documents. Surfaced during the `v0.0.1-rc3` on-device test.

## Fix

Pass a `downloadBase` to `WhisperKit(model:downloadBase:load:)` pointing at **`~/Library/Application Support/FreeFlow`**. Application Support is **not** TCC-protected, so:

- no Documents-folder prompt — the model downloads silently on first launch;
- nothing lands in the user's Documents;
- it still lives outside any sandbox container and survives reinstalls (unchanged from today), and is the conventional home for app model data.

`~/Library/Application Support` (persistent) is chosen over `~/Library/Caches` (which macOS may purge under disk pressure, causing a surprise ~240 MB re-download).

## No migration — fresh folder only

The relocation deliberately does **not** move an existing `~/Documents/huggingface` cache. **Why:** *reading* the old location requires Documents access — which would re-trigger the very prompt this removes, defeating the purpose. Instead the new Application Support folder is created fresh and WhisperKit downloads into it. Pre-1.0 there are effectively no installs to migrate; an old folder, if present, is inert and can be deleted manually.

## Implementation

- `TranscriptionService.modelDownloadBase()` — internal, pure helper returning the Application Support URL (subfolder name from `Constants`), unit-tested to resolve under Application Support and never `~/Documents`.
- `loadModel` creates that directory and passes it as `downloadBase`; `load: true` and its rationale are preserved (the single model-load site stays in `TranscriptionService`).

## Acceptance criteria

1. On a machine with no prior cache, first launch downloads the model into `~/Library/Application Support/FreeFlow/…` with **no Documents-folder prompt**, and dictation works.
2. A unit test asserts `modelDownloadBase()` resolves under Application Support, not Documents.
3. [../architecture/distribution.md](../architecture/distribution.md) and the README reflect the new location.

## Related

- [../architecture/distribution.md](../architecture/distribution.md) — the model-cache section this updates
- [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md) — the "model cache trusted without verification" trade-off; relocating the cache doesn't change that trust model
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — where the transcription/model-load step sits
