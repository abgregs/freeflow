# River

**Dictation that follows you wherever you go.**

Hold (or tap) a key, speak, and your words appear at the cursor — in any app you can type into, transcribed entirely on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit).

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=for-the-badge)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey?style=for-the-badge)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)

- Works everywhere you type — Slack, browser, terminal, IDE.
- Three activation modes (Hold, Single Tap, Double Tap) on your choice of ten keys.
- Text is typed straight in; your clipboard is never touched.
- 100% on-device — no account, no telemetry, no subscription.

First launch downloads the default model (~240 MB) into `~/Library/Application Support/River`. Everything after that is offline.

## Install

```bash
brew install --cask abgregs/river/river
```

Or download the signed, notarized [`.dmg`](https://github.com/abgregs/river/releases/latest) and drag River to Applications. Requires macOS 14+ on Apple Silicon.

## Build from source

Only the Xcode Command Line Tools are needed (`xcode-select --install`).

1. One-time: create a self-signed certificate named "River Dev" (Keychain Access → Certificate Assistant → Create a Certificate → Self Signed Root → Code Signing). Details in [docs/architecture/distribution.md](docs/architecture/distribution.md).
2. Build and install:
   ```bash
   git clone https://github.com/abgregs/river.git
   cd river
   swift build              # debug build
   swift test               # test suite
   make install             # release + sign + install to /Applications
   ```
3. Grant Microphone, Input Monitoring, and Accessibility when onboarding prompts you. Granting these to a self-built binary is a high-trust action — see [what you're trusting](docs/architecture/distribution.md).

Contributors: start at [docs/_index.md](docs/_index.md) — conventions, architecture, and the roadmap all live there.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Argmax, MIT) — the on-device transcription engine
- [Whisper](https://github.com/openai/whisper) (OpenAI, MIT) — the speech models; code and weights are both MIT
- [swift-transformers](https://github.com/huggingface/swift-transformers) and [swift-jinja](https://github.com/huggingface/swift-jinja) (Hugging Face, Apache-2.0) — tokenizer and model-hub plumbing
- Apple's [swift-argument-parser](https://github.com/apple/swift-argument-parser), [swift-collections](https://github.com/apple/swift-collections), [swift-crypto](https://github.com/apple/swift-crypto), and [swift-asn1](https://github.com/apple/swift-asn1) (Apache-2.0), plus [yyjson](https://github.com/ibireme/yyjson) (MIT) — transitive via WhisperKit

Models are downloaded at runtime from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml); this repository redistributes no model weights.

## License

[MIT](LICENSE) — every dependency is MIT or Apache-2.0.
