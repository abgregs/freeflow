# Architecture: Release Pipeline

How a public release is built, signed, notarized, and published. The pipeline is
[`.github/workflows/release.yml`](../../.github/workflows/release.yml); it
implements the security requirements in
[../planning/0005_release-pipeline-security.md](../planning/0005_release-pipeline-security.md).

> **Status (2026-06-22): in production.** The pipeline ran on the `v0.1.0` tag —
> it produced a Developer-ID-signed, notarized, stapled `FreeFlow-0.1.0.dmg` +
> its SHA-256, published to the GitHub Release and feeding the live Homebrew tap.
> M11's exit criteria are met; the flow below is the proven release path, not a draft.

## What it does

On a `v*` tag push, on an Apple Silicon runner:

1. Checks out the tagged commit (build provenance — the tag is the only input).
2. Extracts the tag's `## [x.y.z]` section from `CHANGELOG.md`
   ([`scripts/extract-changelog`](../../scripts/extract-changelog)) — a real
   release with no section **fails here**, before anything is signed or
   published; a suffixed pre-release tag falls back to generated notes
   (planning 0013). Then stamps the version from the tag into `Info.plist`.
3. Imports the Developer ID cert into an **ephemeral keychain**.
4. `make verify` — builds release, assembles the bundle, signs with Developer ID
   (`--options runtime`), and runs the `codesign -dv` identifier check. Passes
   `SWIFT_FLAGS=-Xswiftc -DFREEFLOW_RELEASE` so the dev-only Skip button is
   compiled out (see [permissions.md](permissions.md)).
5. Notarizes the app via `notarytool --wait`, staples it.
6. Packages the DMG ([`scripts/make-dmg`](../../scripts/make-dmg)), signs,
   notarizes, and staples it.
7. EdDSA-signs the DMG with `sign_update` and writes a single-item Sparkle
   appcast ([`scripts/make-appcast`](../../scripts/make-appcast)) — planning 0009.
8. Publishes the DMG + a SHA-256 checksum + `appcast.xml` to the GitHub
   Release, with the curated `CHANGELOG.md` section as the release body (the
   same text feeds the appcast `<description>`).
9. Renders the cask template ([`packaging/homebrew/freeflow.rb`](../../packaging/homebrew/freeflow.rb))
   with the new `version` + published `sha256` and pushes it to the tap repo's
   `Casks/freeflow.rb` via `TAP_BUMP_TOKEN` — releases only, never
   pre-releases (planning 0013).
10. Tears down the keychain and key material — even on failure.

`SUFeedURL` points at `/releases/latest/download/appcast.xml`, which always
resolves to the newest **non-pre-release** release's asset. Each release attaches
its own single-item appcast listing itself; Sparkle offers the highest
`CFBundleVersion` it sees, so one item is enough and the pipeline stays stateless
(no need to carry every past DMG forward to rebuild a cumulative feed). Suffixed
test tags publish as pre-releases and are therefore invisible to Sparkle users.

## Required GitHub secrets

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Base64 of the exported Developer ID Application cert + key (`.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that `.p12` |
| `SIGNING_IDENTITY` | Full identity string, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_API_KEY_BASE64` | Base64 of the App Store Connect API key (`.p8`) |
| `NOTARY_API_KEY_ID` | The API key's Key ID |
| `NOTARY_API_ISSUER_ID` | The API key's Issuer ID |
| `SPARKLE_PRIVATE_KEY` | Base64 EdDSA private key that signs the Sparkle appcast (planning 0009) |
| `TAP_BUMP_TOKEN` | Fine-grained PAT, `contents: write` on `abgregs/homebrew-freeflow` **only** — pushes the rendered cask on each release (planning 0013) |

App Store Connect API key is used over an Apple ID + app-specific password — it
is revocable, has no 2FA interactivity, and scopes to notarization.

The Sparkle EdDSA key is independent of Apple's Developer ID signing — it is
Sparkle's own integrity check on the downloaded update. The workflow pipes it to
`sign_update` over **stdin** (never a file or a command argument), and
`sign_update` ships inside the Sparkle SwiftPM artifact, integrity-verified by
SPM against the checksum pinned in `Package.resolved` — so the appcast step adds
no unpinned action or extra download (0005 workflow hardening).

## One-time setup

1. Enroll in the Apple Developer Program; create a **Developer ID Application**
   certificate; export it from Keychain Access as a `.p12`.
2. In App Store Connect, create an API key with the **Developer** role; download
   the `.p8` (one-time download) and note the Key ID + Issuer ID.
3. `base64 -i cert.p12 | pbcopy` (and the `.p8`) into the secrets above.
4. Confirm tag protection is active (it is — see [../conventions/git.md](../conventions/git.md)).
5. **Sparkle keypair (one-time, planning 0009):** generate the EdDSA keypair with
   the `generate_keys` tool that ships in the Sparkle SwiftPM artifact (after a
   `swift build`, it lives under
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys`). Running it prints the
   **public** key and stores the **private** key in your login Keychain. Then:
   - Paste the printed public key into `SUPublicEDKey` in
     [`Info.plist`](../../Sources/FreeFlow/Resources/Info.plist), replacing the
     `REPLACE_WITH_SPARKLE_ED_PUBLIC_KEY` placeholder.
   - Export the private key (`generate_keys -x private-key.txt`), base64-encode
     it (`base64 -i private-key.txt | pbcopy`), and store it as the
     `SPARKLE_PRIVATE_KEY` secret. **Never commit the private key.**

   Until both are in place, builds still ship, but Sparkle updates fail signature
   verification (safe-by-default) and the appcast step fails loudly on the
   missing secret.
6. **Tap-bump token (one-time, planning 0013):** create a **fine-grained PAT**
   restricted to the `abgregs/homebrew-freeflow` repository with the
   `Contents: Read and write` permission and nothing else; store it as the
   `TAP_BUMP_TOKEN` secret. Least-privilege and revocable — it cannot touch
   this repo. The tap-bump step fails loudly if it's unset.

## Cutting a release

1. Rename `CHANGELOG.md`'s `## [Unreleased]` section to `## [x.y.z] - <date>` —
   that rename is the deliberate "these are the release notes" moment; the
   workflow only reads it, never writes prose. A missing section fails the
   release before any artifact is built.
2. Tag:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Then: watch the Action and confirm the Release has `FreeFlow-0.1.0.dmg` +
`.dmg.sha256` + `appcast.xml` with the changelog section as its body, and that
the tap's `Casks/freeflow.rb` was bumped (release notes and cask are both
automated — planning 0013). Releases are **immutable** — to fix a bad build,
tag a new version; never replace an asset under an existing tag. If only the
tap-bump step fails, the release is already live: fix the cause and re-run the
failed job, or fall back to the manual copy described in
[../../packaging/homebrew/README.md](../../packaging/homebrew/README.md).

The workflow validates the tag is `vX.Y.Z` (or `vX.Y.Z-suffix`) and fails fast
otherwise, before any signing.

### Test runs

There is no dry-run mode and tags can't be deleted (tag protection), so the
safe way to exercise the pipeline end-to-end is a **suffixed pre-release tag**:

```bash
git tag v0.0.1-rc1 && git push origin v0.0.1-rc1
```

A suffixed tag is published as a GitHub **pre-release** (its numeric core,
`0.0.1`, goes into `CFBundleShortVersionString`). Verify the produced DMG is
genuinely notarized before trusting the real release:

```bash
spctl -a -vvv -t install FreeFlow-0.0.1-rc1.dmg   # should report "accepted / Notarized Developer ID"
stapler validate FreeFlow-0.0.1-rc1.dmg
```

## Related

- [distribution.md](distribution.md) — the three channels and signing identities
- [../planning/0005_release-pipeline-security.md](../planning/0005_release-pipeline-security.md) — the checklist this satisfies
- [../../packaging/homebrew/README.md](../../packaging/homebrew/README.md) — the cask the DMG feeds
