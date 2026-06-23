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
2. Stamps the version from the tag into `Info.plist`.
3. Imports the Developer ID cert into an **ephemeral keychain**.
4. `make verify` — builds release, assembles the bundle, signs with Developer ID
   (`--options runtime`), and runs the `codesign -dv` identifier check. Passes
   `SWIFT_FLAGS=-Xswiftc -DFREEFLOW_RELEASE` so the dev-only Skip button is
   compiled out (see [permissions.md](permissions.md)).
5. Notarizes the app via `notarytool --wait`, staples it.
6. Packages the DMG ([`scripts/make-dmg`](../../scripts/make-dmg)), signs,
   notarizes, and staples it.
7. Publishes the DMG + a SHA-256 checksum to the GitHub Release.
8. Tears down the keychain and key material — even on failure.

## Required GitHub secrets

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Base64 of the exported Developer ID Application cert + key (`.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that `.p12` |
| `SIGNING_IDENTITY` | Full identity string, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_API_KEY_BASE64` | Base64 of the App Store Connect API key (`.p8`) |
| `NOTARY_API_KEY_ID` | The API key's Key ID |
| `NOTARY_API_ISSUER_ID` | The API key's Issuer ID |

App Store Connect API key is used over an Apple ID + app-specific password — it
is revocable, has no 2FA interactivity, and scopes to notarization.

## One-time setup

1. Enroll in the Apple Developer Program; create a **Developer ID Application**
   certificate; export it from Keychain Access as a `.p12`.
2. In App Store Connect, create an API key with the **Developer** role; download
   the `.p8` (one-time download) and note the Key ID + Issuer ID.
3. `base64 -i cert.p12 | pbcopy` (and the `.p8`) into the secrets above.
4. Confirm tag protection is active (it is — see [../conventions/git.md](../conventions/git.md)).

## Cutting a release

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Then: watch the Action, confirm the Release has `FreeFlow-0.1.0.dmg` +
`.dmg.sha256`, and bump the Homebrew cask
([../../packaging/homebrew/README.md](../../packaging/homebrew/README.md)).
Releases are **immutable** — to fix a bad build, tag a new version; never
replace an asset under an existing tag.

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
