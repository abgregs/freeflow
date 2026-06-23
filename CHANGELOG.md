# Changelog

All notable changes to Free Flow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(see [docs/conventions/versioning-and-releases.md](docs/conventions/versioning-and-releases.md)).

## [Unreleased]

## [0.1.0] - 2026-06-22

First public release — a macOS menu bar dictation app with fully on-device transcription.

### Added
- Dictation cycle: hold (or tap) an activation key, speak, and the text is typed in at your cursor.
- Three activation modes — Hold (push-to-talk), Single Tap, and Double Tap.
- Configurable activation key with ten modifier-key options (default: Right Option).
- On-device transcription via WhisperKit (`small.en`, ~240 MB, downloaded on first launch); no audio or text ever leaves your Mac.
- Keystroke-injection text insertion — your clipboard is never read or written.
- A guard that skips non-editable targets, so dictation can't fire text into the wrong place.
- Live settings: activation key and mode changes apply instantly, no restart.
- Launch at login.
- Guided onboarding for the Microphone, Input Monitoring, and Accessibility permissions.
- Menu bar status that tracks the cycle (Ready → Recording → Processing) and surfaces errors.
- Signed and notarized `.dmg`, plus a Homebrew cask (`brew install --cask abgregs/freeflow/freeflow`).

[Unreleased]: https://github.com/abgregs/free-flow/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/abgregs/free-flow/releases/tag/v0.1.0
