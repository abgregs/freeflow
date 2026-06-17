# Planning: In-App Auto-Update via Sparkle (roadmap 0009)

V1 ships with no auto-update: a user who installed the `.dmg` has no way to learn a newer version exists short of manually checking the Releases page (the update gap recorded in [../architecture/distribution.md](../architecture/distribution.md)). Homebrew users fare better — `brew upgrade` is pull-based — but the direct-download channel, which is most users, is stuck. [Sparkle](https://sparkle-project.org) is the standard auto-update framework for non-App-Store Mac apps; this adds it.

## Mechanism

Sparkle embeds an updater that periodically fetches an **appcast** (an XML feed listing available versions, each with a download URL, version, and signature). When a newer build exists it shows an "Update available" prompt, downloads the new artifact, verifies its signature, and replaces the app in place.

Two signatures are in play and must not be conflated:

- **Developer ID + notarization** — Apple's trust, already handled by the release pipeline.
- **Sparkle EdDSA signature** — Sparkle's *own* integrity check on the update, signed with a private key you hold; the app embeds the matching public key (`SUPublicEDKey`). Independent of Apple's signing.

## Implementation sketch

- Add **Sparkle** as a Swift Package dependency; wire a `SPUStandardUpdaterController` and a "Check for Updates…" menu item.
- `Info.plist`: `SUFeedURL` (the appcast URL) and `SUPublicEDKey` (the Sparkle public key).
- Generate the Sparkle EdDSA keypair once; store the **private** key as a CI secret alongside the Developer ID secrets (see [release-pipeline.md](../architecture/release-pipeline.md)).
- **Host the appcast** over HTTPS — GitHub Pages or a file attached to Releases — listing each release's DMG, version, and signature.
- **Extend the release workflow:** after publishing the DMG, run Sparkle's `sign_update` on it and append/update the appcast entry, so a single `git push origin vX.Y.Z` ships the build *and* notifies every Sparkle user. This is the payoff of the tag-driven pipeline.
- Mark the Homebrew cask `auto_updates true` so Homebrew defers to Sparkle instead of fighting it on `brew upgrade`.
- Relies on a monotonic `CFBundleVersion`, already guaranteed by the workflow (see [../conventions/versioning-and-releases.md](../conventions/versioning-and-releases.md)).

## Security / privacy notes

- The appcast must be served over **HTTPS** (Sparkle requires it) and updates must be **EdDSA-signed** — together they defend against a tampered or substituted update.
- An update check is a periodic network request to the appcast host — the **second** network behavior in an otherwise on-device app (the first is the WhisperKit model download). Keep it transparent and consider asking on first launch whether to enable automatic checks, consistent with the privacy posture ([../requirements/core-feature.md](../requirements/core-feature.md) item 6).

## Acceptance criteria

1. A user on version N running a Sparkle-enabled build is offered an update when N+1 is released; installing it replaces the app and relaunches cleanly.
2. The update's EdDSA signature is verified; a tampered DMG is rejected.
3. The release workflow signs the update and updates the appcast on a tag push — no manual appcast editing.
4. The Homebrew cask is marked `auto_updates true` so the two channels don't conflict.
5. The first-launch / update-check behavior is documented and consistent with the privacy posture.

## Related

- [../architecture/distribution.md](../architecture/distribution.md) — the channels and the update gap this closes
- [../architecture/release-pipeline.md](../architecture/release-pipeline.md) — the pipeline this extends with appcast signing
- [../conventions/versioning-and-releases.md](../conventions/versioning-and-releases.md) — the version fields Sparkle compares
