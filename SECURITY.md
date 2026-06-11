# Security Policy

## Reporting a vulnerability

Please don't open a public issue for security problems. Use GitHub's
private vulnerability reporting instead: **Security tab → Report a
vulnerability** on this repository.

Reports get an acknowledgment within a few days. Free Flow is a personal
open-source project with no bounty program, but security reports are taken
seriously: this app runs with Microphone, Input Monitoring, and
Accessibility permissions, and anything that weakens that trust is treated
as a priority.

## Scope

The app, the build/install pipeline (`Makefile`), and release artifacts.
Model files are downloaded from Hugging Face at runtime; issues in the
models or in WhisperKit itself should be reported upstream to Argmax.

## Supported versions

Only the latest release receives security fixes.
