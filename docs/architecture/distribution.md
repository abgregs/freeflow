# Architecture: Distribution

Three channels, two signing identities, one stable bundle ID.

## Channels

1. **Source build** (devs) — clone, run `swift build`, install via the Makefile target. Local-signed.
2. **Homebrew cask** (power users) — `brew install --cask abgregs/freeflow/freeflow` (from the `abgregs/homebrew-freeflow` tap) pulls the latest signed `.dmg`.
3. **GitHub Releases `.dmg`** (general users) — signed and notarized, drag-to-`/Applications`.

The App Store is intentionally not a channel. **Why:** the sandbox forbids global event taps, which would require redesigning the activation hotkey around a much weaker mechanism. See [overview.md](overview.md).

## Two signing identities

| Identity | Used by | Source | Lifetime |
|---|---|---|---|
| **Free Flow Dev** | Local installs via Makefile | Self-signed certificate in user's login keychain | Persistent across rebuilds on a developer machine |
| **Developer ID Application** | DMG releases and Homebrew cask | Apple Developer Program ($99/yr) | Tied to the Apple developer account |

Local builds always use Free Flow Dev. **Why:** ad-hoc signing produces a new code-directory hash on every build, which invalidates TCC entries (Accessibility / Input Monitoring), forcing the user to re-grant permissions every rebuild. A persistent local identity keeps the same hash, so TCC grants stick.

Release builds use Developer ID. **Why:** macOS Gatekeeper warns sharply on Developer ID-unsigned downloads; for an app that asks for Accessibility this kills trust. Developer ID + notarization makes the app a first-class macOS citizen.

## What a source-build contributor is trusting

Two facts to understand before running `make install` and granting permissions:

- **The self-signed certificate is not scoped to Free Flow.** Once "Free Flow Dev" exists in the login keychain, any process running as your user can sign with it. It confers no system trust — Gatekeeper still treats the result as unidentified. Its only job is keeping the code-directory hash (and therefore TCC grants) stable across rebuilds.
- **Granting Microphone + Input Monitoring + Accessibility to a self-built, non-notarized binary is the highest-trust permission set macOS has.** Nothing vouches for the binary except the source you built it from. The architecture keeps that reading tractable: each gated OS call has exactly one call site, in the corresponding [capability](capabilities.md).

## Bundle ID is load-bearing

The bundle ID is `com.freeflow.app`. It must:

1. Be present in `Info.plist` as `CFBundleIdentifier`.
2. Match what's inside the `.app/Contents/MacOS/FreeFlow` binary's code signature.
3. Stay stable across versions.

**Why:** TCC keys all permission grants by bundle ID + code signature. Changes to either look like a different app. Users see ghost entries in System Settings → Privacy & Security → Accessibility and have to re-grant. Most users will give up. See [permissions.md](permissions.md).

A bundle without `Info.plist` (or with a different `CFBundleIdentifier` than the binary) is *worse* than no signature at all: macOS may accept it for Input Monitoring but refuse synthetic key event posting (silently). This is exactly the failure mode that bricks the paste pipeline.

## The build script must produce a valid bundle

This is non-negotiable and documented in [../conventions/anti-patterns.md](../conventions/anti-patterns.md). Specifically:

- `.app/Contents/Info.plist` must exist and contain `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion`, `CFBundleShortVersionString`, `LSUIElement`, `NSMicrophoneUsageDescription`.
- `.app/Contents/Resources/` may be empty but must exist.
- `codesign` must be invoked with `--entitlements path/to/FreeFlow.entitlements --sign "Free Flow Dev"` (or Developer ID for releases).

Prefer using `xcodebuild` or `swift build` plus a tightly verified bundle-assembly step over a hand-rolled script. If a hand-rolled script is unavoidable, its first commit must include a check that `codesign -dv` on the output reports the expected bundle ID.

## WhisperKit model cache

First launch downloads the model identified by `Constants.defaultModel` (currently `openai_whisper-small.en`, ~240 MB) to `~/Library/Application Support/FreeFlow/models/argmaxinc/whisperkit-coreml/<model>` (set via WhisperKit's `downloadBase`). Subsequent launches reuse the cached copy — only the first run sees the download cost. **Application Support, not WhisperKit's `~/Documents/huggingface` default:** Documents is TCC-protected, so downloading there triggers an "access your Documents folder" prompt and clutters the user's Documents — see [../planning/0010_relocate-model-cache.md](../planning/0010_relocate-model-cache.md).

The sandbox is intentionally off (see [permissions.md](permissions.md)), so the cache lives outside the app container and survives reinstalls. This is the **only** network behaviour in the app (see [../requirements/core-feature.md](../requirements/core-feature.md) item 6).

## Releases

- Tag a release: `git tag vX.Y.Z && git push origin vX.Y.Z`. `v*` tags are protected — deletion and force-push are blocked (see [../conventions/git.md](../conventions/git.md)).
- [`.github/workflows/release.yml`](../../.github/workflows/release.yml) builds the tagged commit, signs with Developer ID (reusing `make` so the bundle-integrity check from [anti-pattern #3](../conventions/anti-patterns.md) runs on the release build too), notarizes the app and the DMG via `xcrun notarytool`, staples both, and publishes the `.dmg` + a SHA-256 checksum to the GitHub Release. Required secrets, one-time setup, and how to cut a release are in the [release-pipeline runbook](release-pipeline.md). First run: `v0.1.0` (2026-06-22).
- The Homebrew cask ([`../../packaging/homebrew/freeflow.rb`](../../packaging/homebrew/freeflow.rb)) points at the release `.dmg` and pins its published `sha256`.

Versioning rules and the tag-driven protocol are in [../conventions/versioning-and-releases.md](../conventions/versioning-and-releases.md).

## Updates

How an installed copy learns about a newer version differs by channel:

- **GitHub Releases `.dmg`** — no built-in update mechanism today; the user must check the Releases page and re-download. This is the weakest update UX and the motivation for [Sparkle](../planning/0009_sparkle-auto-update.md).
- **Homebrew cask** — pull-based: `brew upgrade` (or `brew upgrade --cask freeflow`) picks up new versions on the user's own schedule; Homebrew never notifies proactively. A release only becomes visible to Homebrew once the cask's `version` + `sha256` are bumped in the tap ([packaging/homebrew](../../packaging/homebrew/README.md)).
- **Source build** — `git pull` + `make install`.

**Planned:** [Sparkle](../planning/0009_sparkle-auto-update.md) adds in-app "Update available" notifications for the DMG channel — the standard mechanism for non-App-Store Mac apps — driven by an appcast the release workflow publishes on each tag.

## Related

- [permissions.md](permissions.md) — bundle-ID stability and the TCC story
- [overview.md](overview.md) — why MAS is intentionally not a channel
- [release-pipeline.md](release-pipeline.md) — the tag-triggered build/sign/notarize/publish workflow
- [../conventions/versioning-and-releases.md](../conventions/versioning-and-releases.md) — versioning protocol and per-channel update behavior
