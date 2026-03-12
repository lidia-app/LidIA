# Contributing to LidIA

Thank you for your interest in contributing! LidIA is a local-first macOS meeting assistant, and we welcome contributions of all kinds.

## Getting Started

### Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ with Swift 6.2
- Apple Silicon Mac (required for MLX inference)

### Setup

```bash
git clone https://github.com/lidia-app/LidIA.git
cd LidIA
./run.sh        # Build + package .app bundle + launch
```

**Important:** Always use `./run.sh` instead of `swift run`. The app needs a `.app` bundle for macOS TCC permissions (Calendar, Microphone, Notifications).

Other commands:
- `./run.sh build` — Build only
- `swift build` — Compile check (no .app bundle)
- `swift test` — Run tests

### Architecture

See [CLAUDE.md](CLAUDE.md) for detailed project structure, architecture patterns, and conventions. Key points:

- **SwiftUI + SwiftData** with `@Observable` pattern
- **Actor isolation** for thread-safe network clients
- **Protocol abstractions** — `LLMClient`, `STTEngine`, `ChatStream`
- **Swift 6.2 strict concurrency** — all sendability requirements must be satisfied
- **`@MainActor`** on all UI-facing classes

## How to Contribute

### Adding a New LLM Provider

1. Create an actor conforming to `LLMClient` protocol in `Sources/LidIA/LLM/`
2. Add a case to the `LLMProvider` enum
3. Update `makeLLMClient()` factory in `OllamaClient.swift`

### Adding a New STT Engine

1. Create a class conforming to `STTEngine` protocol in `Sources/LidIA/STT/`
2. Add a case to the `STTProvider` enum

### Adding a New Integration

1. Create a client in `Sources/LidIA/Integrations/`
2. Add settings fields to `AppSettings.swift`
3. Wire into `RecordingSession.stopRecording()` or `PostProcessingService`

## Pull Request Guidelines

1. **Fork and branch** — Create a feature branch from `main`
2. **Test locally** — Run `./run.sh` and verify your changes work
3. **Check both themes** — Verify UI in both light and dark mode
4. **Keep it focused** — One feature or fix per PR
5. **Describe your changes** — Explain what and why, not just how

## Code Style

- Swift 6.2 strict concurrency
- `@Observable` for state, not `ObservableObject`
- Actors for thread-safe network/service clients
- No storyboards — pure SwiftUI
- Toolbar items must have content (no wrapping content in `if` inside `ToolbarItem`)
- Keyboard shortcuts use zero-frame background buttons

## Areas We'd Love Help With

- Speaker diarization (who said what)
- Multi-language transcription support
- Improved meeting templates
- Better action item extraction
- Accessibility improvements
- Performance profiling and optimization
- Test coverage for core business logic

## Reporting Issues

Use [GitHub Issues](https://github.com/lidia-app/LidIA/issues) with these tags:
- `[bug]` — Something isn't working
- `[feat]` — Feature request
- `[fix]` — You have a fix to propose

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
