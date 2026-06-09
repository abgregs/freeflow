# Architecture: Distribution

Three channels, two signing identities, one stable bundle ID.

## Channels

1. **Source build** (devs) — clone, run `swift build`, install via the Makefile target. Local-signed.
2. **Homebrew cask** (power users) — `brew install --cask freeflow` pulls the latest signed `.dmg`.
3. **GitHub Releases `.dmg`** (general users) — signed and notarized, drag-to-`/Applications`.

The App Store is intentionally not a channel. **Why:** the sandbox forbids global event taps, which would require redesigning the activation hotkey around a much weaker mechanism. See [overview.md](overview.md).

## Two signing identities

| Identity | Used by | Source | Lifetime |
|---|---|---|---|
| **Free Flow Dev** | Local installs via Makefile | Self-signed certificate in user's login keychain | Persistent across rebuilds on a developer machine |
| **Developer ID Application** | DMG releases and Homebrew cask | Apple Developer Program ($99/yr) | Tied to the Apple developer account |

Local builds always use Free Flow Dev. **Why:** ad-hoc signing produces a new code-directory hash on every build, which invalidates TCC entries (Accessibility / Input Monitoring), forcing the user to re-grant permissions every rebuild. A persistent local identity keeps the same hash, so TCC grants stick.

Release builds use Developer ID. **Why:** macOS Gatekeeper warns sharply on Developer ID-unsigned downloads; for an app that asks for Accessibility this kills trust. Developer ID + notarization makes the app a first-class macOS citizen.

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

First launch downloads the model identified by `Constants.defaultModel` (currently `openai_whisper-small.en`, ~240 MB) to WhisperKit's cache directory (`~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/<model>`). Subsequent launches reuse the cached copy — only the first run sees the download cost.

The sandbox is intentionally off (see [permissions.md](permissions.md)), so the cache lives outside the app container and survives reinstalls. This is the **only** network behaviour in the app (see [../requirements/core-feature.md](../requirements/core-feature.md) item 6).

## Releases

- Tag a release: `git tag vX.Y.Z && git push origin vX.Y.Z`.
- A GitHub Action (TODO) builds the release `.app`, signs with Developer ID, notarizes via `xcrun notarytool`, staples, packages as `.dmg`, and attaches to the release.
- The Homebrew cask points at the release URL.

## Related

- [permissions.md](permissions.md) — bundle-ID stability and the TCC story
- [overview.md](overview.md) — why MAS is intentionally not a channel
- [../planning/_index.md](../planning/_index.md) — release automation is on the roadmap, not built yet
