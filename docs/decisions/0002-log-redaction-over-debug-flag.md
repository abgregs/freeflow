# ADR 0002: Redact paths at the source instead of gating logs on a debug build flag

**Status:** Accepted — 2026-06-04

## Context

M7 introduced a privacy posture for logging: keep user content out of logs, and gate `privacy: .public` on error strings behind a compile-time `DICTATION_VERBOSE_LOGS` flag (`make DEBUG=true install`), so a distribution build redacts error detail as `<private>` while a developer build shows it.

Reviewing M7 surfaced three problems with that mechanism:

1. **It was adopted once.** Of six `error.localizedDescription` log sites, exactly one (`TextInsertionManager`) used the `#if DICTATION_VERBOSE_LOGS` gate. The other five logged `privacy: .public` unconditionally — so the promised redaction wasn't actually delivered.
2. **The gate was on the wrong log.** The one gated site interpolates an *app-authored* `AccessibilityCapabilityError` (fixed text, no PII). The two genuinely risky sites — WhisperKit's load error and the wrapped `transcriptionFailed(underlying:)` — interpolate *opaque third-party* strings that can embed `/Users/<name>/...` model-cache paths, and those were ungated.
3. **The axis is wrong for this app's support model.** `DICTATION_VERBOSE_LOGS` is compile-time. Non-developer users run the signed release and cannot enable it. So gating *all* error strings would redact the failure reason in exactly the bug reports users submit — blinding field diagnosis of the app's subtlest failures (silent paste, model-load, audio-warmup).

The real privacy facts: user content (transcribed text, dictionary terms) is already protected **structurally — by omission**, never interpolated into a log (only a `.count` is). The residual leak is narrow: a home path carrying the macOS account name, appearing only inside opaque framework error strings.

## Decision

Drop the `DICTATION_VERBOSE_LOGS` build flag entirely. Log error strings `privacy: .public` everywhere, but pass each through `LogRedaction.redactUserPaths(_:)` — a pure helper that replaces `/Users/<name>` with `/Users/<user>` — before logging. Remove the `DEBUG`/verbose-build plumbing and warning from the `Makefile`.

## Rationale

- **Attacks the actual risk, deterministically.** The leak is a path; `redactUserPaths` removes the path at the source. No build mode, no runtime state, no "did this ship with the wrong flag" footgun — the account name is gone before the string is ever interpolated. Fits the app's "structural over discipline, plain code when plain code answers" ethos.
- **Keeps field bug reports diagnosable.** Error *reasons* stay visible in the signed build — the line a user pastes into an issue is readable, minus the username.
- **Uniform and low-judgment.** `redactUserPaths` is idempotent and a no-op on app-authored strings, so it's applied at *every* error-string site without per-site reasoning about whether a value is "opaque enough." One rule, mechanically followed.
- **Honest convention.** The previous rule ("gate error strings behind the flag") described behavior that one of six sites had. The new rule ("omit content; redact paths; log public") matches what the code does at every site.

## Consequences

- `conventions/logging.md` and anti-pattern #4 are rewritten around omission + `LogRedaction` rather than the build flag.
- New error-string log sites must wrap the value in `LogRedaction.redactUserPaths(_:)`. This is the standing tax (one function call), replacing the previous `#if/#else` tax.
- `redactUserPaths` targets the **home-path / account-name** vector specifically. It over-redacts benign `/Users/Shared` (acceptable — no diagnostic value lost) and does **not** scrub other hypothetical PII a framework error might contain. If a new vector appears (e.g. a future cloud feature whose errors echo request data), extend the helper — don't reintroduce a build flag.
- The pure helper has a regression test (`LogRedactionTests`); the account-name-leak intent fails loudly if the regex breaks.

## Revisit if

- **A genuinely sensitive value must be logged conditionally** (not just path-redacted) — e.g. a debugging need to dump buffer contents or a dictionary term. That's a real verbose-mode use case; prefer a **runtime** toggle (a setting the user can enable to reproduce, with a warning) over a compile-time flag, so field users can actually use it.
- **A second PII vector enters error strings.** Extend `LogRedaction` with another rule and a test; keep redaction at the source.
- **A UI path surfaces error text without going through `AppState`.** The menu-bar milestone landed this surface and applied redaction at the `AppState.apply(_:error:)` choke point (see [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)). If a future surface (e.g. the recording HUD) renders an error string by another route, re-apply redaction there — the boundary, not the publisher, is where it belongs.

## Related

- [../conventions/logging.md](../conventions/logging.md) — the omission + redaction rules this ADR establishes.
- [../conventions/anti-patterns.md](../conventions/anti-patterns.md) — item #4, rewritten around this decision.
- [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md) — the capability-failure surface whose error strings these log sites carry.
