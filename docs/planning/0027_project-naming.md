# Planning: Project Naming (roadmap 0027)

The record of the name, why it was chosen, and where it is hardcoded. Kept so that nobody re-litigates the name and so the identity strings are changed together or not at all.

## The name

**River.** Text flows in and follows you from app to app; the 0025 streaming-dictation direction (continuous insertion instead of paste-at-the-end) makes that literal later, and the name gives the design phase a natural language of subtle, fluid motion ([../design/direction.md](../design/direction.md)). The name is model-neutral on purpose: the transcription model may change (Parakeet is under evaluation via the 0022 harness), so nothing in the identity references Whisper.

**Decided 2026-09-15** after a practical clearance pass (USPTO records via public mirrors, the Mac App Store, Setapp, Homebrew, GitHub — not legal advice). Nothing holds rights to "River" in dictation or voice software. Ryver, a team-chat product, is a homophone in neighboring software and was accepted. Names that also cleared and are kept on record in case River is ever revisited: Creek, Diction, Narrate, Aloud, Inlet, Loquy, Spiel, Idiom, Quipster. Namespace availability (domains, GitHub names, cask tokens) was deliberately *not* a criterion; only real legal exposure and fit were.

## Where the identity lives

The name is hardcoded in a small number of load-bearing places. Change them together or not at all.

| Where | String |
|---|---|
| `Makefile:1-3` | `APP_NAME := River`, `BUNDLE_ID := com.river.app`, `SIGN_IDENTITY := River Dev` (must match the self-signed cert in the login keychain) |
| `Sources/River/Resources/Info.plist` | `CFBundleIdentifier`, `CFBundleName`, `CFBundleDisplayName`, `SUFeedURL` (points at `abgregs/river`; baked into every shipped binary) |
| `Sources/River/Utilities/Constants.swift` | `bundleIdentifier`, `loggingSubsystem`, `modelCacheFolderName` (`~/Library/Application Support/River`) |
| `InputMonitoringCapability.swift` | the `com.river.eventtap` thread name (rule 1 in `AGENTS.md`) |
| `Package.swift` | module `River`, test target `RiverTests`; compile condition `RIVER_RELEASE` |
| `.github/workflows/release.yml`, `scripts/make-dmg` | app name, keychain name, `River-x.y.z.dmg`, the tap-bump step targeting `abgregs/homebrew-river` |
| `packaging/homebrew/river.rb` | cask token `river`; install is `brew install --cask abgregs/river/river` (a Homebrew core *formula* named `river` exists, so the bare form is never ours) |

The bundle ID is the one that must never change again: macOS keys every permission grant to it.

## Release status

- **No release exists yet.** The first River release is `v0.1.0`; `CHANGELOG.md`'s Unreleased section holds its notes, and the release is cut per [../architecture/release-pipeline.md](../architecture/release-pipeline.md) once the on-device smoke of the current build passes.
- **Sparkle is configured.** `SUPublicEDKey` holds the real public key; the private key is the `SPARKLE_PRIVATE_KEY` secret. The release workflow fails any tag while that secret is unset, so the first release cannot ship without a working updater ([0009](0009_sparkle-auto-update.md)). The first release is rehearsed with a `v0.1.0-rc1` pre-release tag.

## Related

- [../design/direction.md](../design/direction.md) — what the name should look, move, and sound like
- [0009_sparkle-auto-update.md](0009_sparkle-auto-update.md) — the feed URL and the keypair step
- [0013_release-automation.md](0013_release-automation.md) — the tap-bump step and `TAP_BUMP_TOKEN` scope
- [../architecture/distribution.md](../architecture/distribution.md) — bundle ID, signing identities, cache location
