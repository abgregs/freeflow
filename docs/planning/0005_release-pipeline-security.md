# Planning: Release Pipeline Security Checklist (roadmap 0005)

Hardening requirements for the M11 public release pipeline, captured during the
2026-06 pre-publication security review. The M11 GitHub Action must incorporate
this checklist — it gates M11's exit criteria, it is not a post-V1 enhancement.

## Why this exists

Free Flow runs with Microphone + Input Monitoring + Accessibility granted. A
compromised release pipeline doesn't just ship a bad build — it ships a binary
users will hand the most powerful permission set macOS offers. The pipeline is
part of the attack surface; its integrity guarantees are a feature.

## Checklist

### Workflow hardening

- Pin every GitHub Action to a full commit SHA, not a tag or branch.
- Set explicit least-privilege `permissions:` on the workflow (`contents: write`
  for the release upload; nothing else).
- Trigger only on version tags, and enable tag protection (plus branch
  protection on `main`) once the repo is public. **Why:** a tag push *is* a
  release trigger — anyone who can push a tag can ship a release.

### Secrets

- The Developer ID certificate (`.p12`) and `notarytool` credentials live in
  GitHub encrypted secrets, are imported into an ephemeral keychain on the
  runner, and are removed in a cleanup step that runs even on failure.
- No secret is ever echoed to logs; no `set -x` in release scripts.

### Artifact integrity

- Publish a SHA-256 checksum alongside the `.dmg` on the release page.
- Release artifacts are immutable: never replace an asset under an existing
  tag — fix forward with a new tag.
- The Homebrew cask's mandatory `sha256` field must reference the published
  checksum; it gives users install-time integrity for free.

### Build provenance

- CI builds from the committed `Package.resolved` (default `swift build`
  behavior). Never run `swift package update` in CI.
- Build from the tagged commit only — no workflow inputs that build arbitrary
  refs.

### Release-build behavior

- **Resolved (2026-06-15):** the onboarding "Skip (I've already granted
  permissions)" button is **hidden in notarized builds** and kept in
  local/self-signed builds, gated by the `FREEFLOW_RELEASE` compile condition
  the release workflow sets (`-Xswiftc -DFREEFLOW_RELEASE`). Its rationale —
  unreliable TCC detection on unsigned dev builds (see
  [../requirements/core-feature.md](../requirements/core-feature.md)) — doesn't
  apply to a notarized app, where stable-signature detection is reliable and a
  Skip would only let a user bypass a still-required permission.

## Acceptance criteria

1. The M11 workflow file passes review against every item above before the
   first public tag is pushed. **Status (2026-06-22): done.** The workflow
   ([../../.github/workflows/release.yml](../../.github/workflows/release.yml))
   satisfies every checklist item — SHA-pinned action, least-privilege
   `permissions`, ephemeral keychain with always-run teardown, `Package.resolved`
   provenance, published SHA-256 — and ran on the `v0.1.0` tag, so the first-run
   review on a `v*` tag is complete. See the
   [release-pipeline runbook](../architecture/release-pipeline.md).
2. A released `.dmg`'s checksum matches both the published SHA-256 and the
   cask's `sha256`.
3. Tag and branch protection are verified in repository settings after the repo
   goes public. **Status (2026-06-14):** done ahead of the pipeline — the repo
   is already public, so the "once public" hardening landed now: `main` and `v*`
   tag rulesets are active (see [../conventions/git.md](../conventions/git.md)),
   and private vulnerability reporting is enabled (backing the promise in
   [SECURITY.md](../../SECURITY.md)). The workflow-hardening and secrets items
   above still gate the M11 Action itself.

## Related

- [milestones.md](milestones.md) — M11, the pipeline this gates
- [../architecture/distribution.md](../architecture/distribution.md) — channels and signing identities
- [0006_runtime-security-hardening.md](0006_runtime-security-hardening.md) — the same review's runtime findings
