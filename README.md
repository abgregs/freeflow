# River

A macOS menu bar dictation app. Press (or tap) a configurable modifier key, speak, and your words appear as text at your cursor — all transcribed on-device with WhisperKit.

> **Status:** M1 (walking skeleton) complete — runnable menu bar app, no feature code yet. Active focus tracked in [`docs/planning/current-focus.md`](docs/planning/current-focus.md).

## For users

Not ready for users. When it is, you'll be able to:

```bash
brew install --cask river
```

…or download a signed `.dmg` from the GitHub releases page.

## For contributors

1. **Read the docs.** Start at [`docs/_index.md`](docs/_index.md). Project context, conventions, architecture, and the roadmap all live there.
2. **One-time setup** for local installs: create a self-signed code-signing certificate named "River Dev" in Keychain Access (Certificate Assistant → Create a Certificate → Self Signed Root → Code Signing). See [`docs/architecture/distribution.md`](docs/architecture/distribution.md).
3. **Build the app:**
   ```bash
   git clone <repo>
   cd river
   swift build              # debug build
   make install             # release + sign + install to /Applications
   ```
4. **Grant permissions:** Microphone, Input Monitoring, and Accessibility (the last one must be added manually in System Settings → Privacy & Security → Accessibility). The onboarding window will walk you through this.

## For agents (Claude Code, etc.)

Read [`CLAUDE.md`](CLAUDE.md). Run `/brief` before non-trivial code changes and `/debrief` after.

## License

MIT — see [LICENSE](LICENSE).
