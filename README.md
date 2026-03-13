[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-26+-blue.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Website](https://img.shields.io/badge/Website-lidia--app.github.io-ff4fa3)](https://lidia-app.github.io)

# LidIA

> **[lidia-app.github.io](https://lidia-app.github.io)** — See it in action

A native macOS meeting intelligence app — transcribe, summarize, and chat with your meetings using local or cloud AI.

**Local-first by default.** LidIA runs entirely on your Mac with no data leaving your device. Optionally connect cloud providers (OpenAI, Anthropic) for faster or more capable models.

## Features

### Core
- **Real-time transcription** — Apple Speech, WhisperKit, or NVIDIA Parakeet (all on-device)
- **AI-powered summaries** — Automatic title, multi-section summary, decisions, and action items
- **Meeting templates** — General, 1:1, Brainstorm, Standup — or create your own
- **Chat with any meeting** — Ask questions about transcripts and summaries with conversational AI
- **Action item tracking** — Extracted automatically, tracked across meetings
- **Global search** — Cmd+K to search across all meetings

### Voice Assistant
- **Push-to-talk** — Hotkey-activated voice assistant with animated orb UI
- **Meeting context** — Ask about your action items, upcoming meetings, past discussions
- **Fully local option** — Parakeet STT + MLX LLM + System TTS (no API keys needed)
- **Cloud option** — OpenAI for lower latency when preferred

### Integrations
- **Google Calendar** — See upcoming events, one-click recording, auto-detect meetings
- **Apple Calendar & Reminders** — Native EventKit integration
- **Notion** — Push meeting notes to your Notion database
- **n8n webhooks** — Trigger any automation (Slack, email, CRM) after meetings

### UX
- **Floating transcript** — Live overlay showing words as they're captured
- **Speaker separation** — Mic vs system audio diarization with chat bubble UI
- **Menu bar** — Quick access from the macOS menu bar
- **Keyboard shortcuts** — Cmd+1-5 for tabs, Cmd+R to record, Cmd+K to search

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ / Swift 6.2 (for building from source)
- Apple Silicon recommended (for local MLX inference)

## Build & Run

```bash
git clone https://github.com/lidia-app/LidIA.git
cd LidIA
./run.sh
```

> **Important:** Always use `./run.sh` instead of `swift run`. The app needs a proper `.app` bundle for macOS TCC permissions (Microphone, Calendar, Reminders, Notifications) to work correctly.

Other commands:
```bash
./run.sh build    # Build only (creates .build/LidIA.app)
./run.sh clean    # Remove .app bundle
swift build       # Compile check only (no .app bundle)
swift test        # Run tests
```

Or open `Package.swift` in Xcode 26+ and run from there.

## Setup

1. **Launch LidIA** — it works out of the box with local models (no API keys needed)
2. **Download an MLX model** — Go to Settings (Cmd+,) → Models → Download a model (Qwen3 4B recommended, ~2.3 GB)
3. **Grant permissions** when prompted — Microphone access is required for recording
4. **Optional: Cloud providers** — Add API keys for OpenAI or Anthropic in Settings for cloud LLM/TTS
5. **Optional: Integrations:**
   - Google Calendar — Create OAuth credentials in [Google Cloud Console](https://console.cloud.google.com/), enter Client ID/Secret in Settings
   - Notion — Create an [internal integration](https://www.notion.so/my-integrations), enter API key
   - n8n — Enter your webhook URL for post-meeting automation
   - Apple Calendar/Reminders — Grant access when prompted

## Usage

1. Click **Record** (or click the record button on an upcoming calendar event) to start a meeting
2. A floating transcript panel appears showing live transcription
3. Click **Stop** to end — LidIA automatically refines the transcript, generates a summary, and extracts action items
4. Use **Cmd+K** to search across all your meetings
5. Click into any meeting to view Summary, Transcript, Notes, Action Items, or Chat
6. Press your voice hotkey (default: Option+Space) to talk to the voice assistant

## Architecture

Built with SwiftUI + SwiftData on macOS 26. Key patterns:

- **`@Observable`** for all state classes
- **Actors** for thread-safe network clients (Ollama, OpenAI, Anthropic, Google Calendar)
- **Protocol abstractions** for pluggable STT engines (`STTEngine`) and LLM providers (`LLMClient`)
- **SwiftData** for persistence, **Keychain** for secrets, **UserDefaults** for preferences
- **Local-first** — MLX for on-device LLM inference, Parakeet/WhisperKit for on-device STT

See [CLAUDE.md](CLAUDE.md) for detailed project structure and development guide.

## LLM Providers

| Provider | Type | Best For |
|----------|------|----------|
| **MLX** | Local (on-device) | Privacy, offline use, free |
| **Ollama** | Local (server) | Larger models, GPU offload |
| **OpenAI** | Cloud | Highest quality, fastest |
| **Anthropic** | Cloud | Claude models |

## STT Engines

| Engine | Type | Notes |
|--------|------|-------|
| **Parakeet** | Local | NVIDIA's streaming ASR, best accuracy |
| **WhisperKit** | Local | OpenAI Whisper on Apple Silicon |
| **Apple Speech** | Local | Built-in, no download needed |

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes and ensure `swift build` passes
4. Commit with clear messages
5. Push to your fork and open a Pull Request

### Development Tips

- Read [CLAUDE.md](CLAUDE.md) for project structure, conventions, and common tasks
- Use `swift build` for quick compile checks, `./run.sh` for full app testing
- Follow existing patterns — `@Observable` for state, actors for network clients
- macOS 26+ APIs are fine — this project targets Tahoe only
- Swift 6.2 strict concurrency — all `Sendable` requirements must be satisfied

### Areas We'd Love Help With

- Multi-language transcription support
- Additional integrations (Slack, Linear, Jira)
- UI/UX improvements
- Documentation and tutorials
- Testing coverage

## Dependencies

See [DEPENDENCIES.md](DEPENDENCIES.md) for a full list of dependencies and their licenses.

## Why "LidIA"?

LidIA is named after Lidia, the creator's mother, as a tribute to her while she fights cancer. The name also nods to the AI at its core — Lid**IA**. Built with love. ❤️

## License

This project is licensed under the [MIT License](LICENSE).
