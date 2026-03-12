# LidIA — Project Context

## What is LidIA?

A native macOS meeting transcription and intelligence app built with SwiftUI + SwiftData. Records meetings, transcribes via Apple Speech / WhisperKit / Parakeet, summarizes via LLM (Ollama, OpenAI, or Anthropic), and integrates with Google Calendar, Apple Calendar, Notion, and n8n.

## Build & Run

```bash
./run.sh             # Build + package .app bundle + launch
./run.sh build       # Build only (creates .build/LidIA.app)
./run.sh clean       # Remove .app bundle
swift build          # Compile check only
swift test           # Run tests
```

**Important:** Always use `./run.sh` instead of `swift run`. The app needs a proper `.app` bundle for macOS TCC permissions (Calendar, Reminders, Microphone, Notifications) to work. `swift run` produces a bare executable that can't request permissions.

**Requirements:** macOS 26 (Tahoe), Xcode 26+, Swift 6.2

## Project Structure

```
Sources/LidIA/
├── LidIAApp.swift                 # App entry — WindowGroup + Settings scenes
├── ContentView.swift              # Main layout — NavigationSplitView + chat panel
├── Settings/
│   └── AppSettings.swift          # @Observable settings (UserDefaults + Keychain)
├── ViewModels/
│   └── ChatBarViewModel.swift     # Chat bar state: messages, streaming, suggestions
├── Views/
│   ├── SettingsView.swift         # Native Settings window (Cmd+,)
│   ├── MeetingListView.swift      # Sidebar — calendar events + past meetings
│   ├── MeetingDetailView.swift    # Detail — inline title + segmented tabs + content
│   ├── ChatBarView.swift          # Bottom chat panel (expand/collapse/close)
│   ├── MeetingChatView.swift      # Per-meeting conversational AI (embedded in tab)
│   ├── ActionItemDashboardView.swift
│   ├── MeetingPrepView.swift      # Pre-meeting prep view
│   ├── PeopleView.swift           # People mentioned across meetings
│   ├── PersonDetailView.swift     # Individual person detail
│   ├── LiveTranscriptView.swift   # Real-time transcript during recording
│   ├── RecordingControlsView.swift
│   ├── SearchBarView.swift        # Cmd+F sidebar search
│   ├── SearchResultsView.swift    # Search results overlay
│   └── FloatingPanel/             # Floating transcript overlay during recording
│       ├── FloatingPanelController.swift
│       ├── FloatingTranscriptView.swift
│       └── RecordingPillController.swift
├── MenuBar/
│   ├── MenuBarController.swift    # NSStatusItem menu bar icon
│   └── MenuBarView.swift          # Menu bar dropdown UI
├── Models/
│   ├── Meeting.swift              # SwiftData @Model
│   ├── ActionItem.swift           # SwiftData @Model
│   ├── TranscriptWord.swift       # Codable value type
│   ├── MeetingTemplate.swift      # Prompt templates for different meeting types
│   ├── TalkingPoint.swift         # Meeting prep talking points
│   └── RelationshipStore.swift    # People / relationship tracking
├── Audio/
│   ├── AudioCaptureManager.swift  # AVAudioEngine mic capture
│   ├── AudioChunk.swift           # PCM sample buffer
│   ├── AudioResampler.swift       # Sample rate conversion
│   ├── SilenceDetector.swift      # RMS-based silence tracking
│   └── SystemAudioCapture.swift   # System audio capture (screen audio)
├── STT/
│   ├── STTEngine.swift            # Protocol
│   ├── AppleSpeechEngine.swift    # Apple Speech framework
│   ├── WhisperKitEngine.swift     # Local Whisper via WhisperKit
│   ├── ParakeetEngine.swift       # NVIDIA Parakeet TDT streaming
│   └── ParakeetBatchProcessor.swift
├── LLM/
│   ├── OllamaClient.swift         # LLMClient protocol + Ollama actor + factory
│   ├── OpenAIClient.swift         # OpenAI-compatible actor
│   ├── AnthropicClient.swift      # Anthropic Claude actor
│   ├── ChatStream.swift           # ChatStream protocol + HTTPChatStream
│   ├── OpenAIWebSocketStream.swift # OpenAI Responses API via WebSocket
│   ├── ModelRouter.swift          # Auto model selection (thinking vs fast)
│   └── MeetingQueryService.swift  # Natural language meeting queries
├── Pipeline/
│   ├── MeetingPipeline.swift      # Refine → Summarize → Extract actions
│   ├── PostMeetingAutomation.swift # Post-processing automation
│   └── WeeklyDigestService.swift  # Weekly meeting digest
├── Recording/
│   └── RecordingSession.swift     # Orchestrates recording lifecycle
├── Export/
│   └── ExportService.swift        # Markdown export + clipboard
├── Search/
│   └── SpotlightIndexer.swift     # Spotlight / CoreSpotlight indexing
├── Integrations/
│   ├── EventKitManager.swift      # Apple Calendar + Reminders (EventKit)
│   ├── GoogleCalendar/
│   │   ├── GoogleCalendarClient.swift
│   │   ├── GoogleCalendarMonitor.swift
│   │   └── GoogleOAuth.swift
│   ├── NotionClient.swift         # Meeting pages
│   └── N8nClient.swift            # Webhook automation
└── Resources/
    ├── Assets.xcassets/           # App icon
    └── Info.plist                 # Bundle config + permissions
```

## UI Architecture

The app follows standard macOS NavigationSplitView conventions:

- **Sidebar** (`MeetingListView`): "Coming Up" calendar events + "Past Meetings" grouped by date, search field, folder filters
- **Detail** (`MeetingDetailView`): Inline header with editable title + segmented Picker (Summary / Transcript / Notes / Action Items / Chat), content below
- **Chat panel** (`ChatBarView`): Docked at bottom of detail area, collapsible via chevron, closeable via X, reopenable via toolbar button. State persisted in `@AppStorage`
- **Toolbar**: Actions only (AI menu, Export, Settings, New Note, Chat toggle). No navigation in toolbar — segmented control lives inline in the detail view
- **Keyboard shortcuts**: Cmd+1–5 for tabs, Cmd+R for record, Shift+Cmd+N for quick note, Cmd+K to focus chat. Implemented via zero-frame background buttons (not toolbar items, which cause ghost capsules on macOS 26)
- **Settings**: Separate macOS Settings scene, not embedded in main window

## Architecture Patterns

- **@Observable** for all state classes (AppSettings, RecordingSession, MeetingQueryService, EventKitManager, GoogleCalendarMonitor, ChatBarViewModel)
- **Environment injection** — AppSettings, RecordingSession, MeetingQueryService, EventKitManager, GoogleCalendarMonitor injected at app level
- **Actors** for thread-safe network clients (OllamaClient, OpenAIClient, AnthropicClient, GoogleCalendarClient, NotionClient, GoogleOAuth)
- **Protocol abstraction** — `LLMClient` protocol with Ollama/OpenAI/Anthropic conformances; `STTEngine` protocol with Apple Speech/WhisperKit/Parakeet conformances; `ChatStream` protocol for streaming chat
- **SwiftData** for persistence (Meeting, ActionItem, TalkingPoint models)
- **UserDefaults + Keychain** for settings (non-sensitive in defaults, API keys/secrets in Keychain)
- **didSet persistence** — all AppSettings properties save eagerly via didSet, no manual save() needed

## Key Conventions

- Swift 6.2 strict concurrency — all sendability requirements must be satisfied
- `@MainActor` on all UI-facing classes
- macOS 26+ APIs — `.buttonStyle(.glass)`, background extension effects
- No storyboards — pure SwiftUI with Info.plist for bundle config
- SPM-only build (no Xcode project needed, though .xcodeproj exists)
- Toolbar items must have content — never wrap content in `if` inside a `ToolbarItem` (causes empty glass capsules on macOS 26). Put the `if` outside the `ToolbarItem` instead
- Keyboard shortcuts use zero-frame background buttons, not hidden toolbar items

## Dependencies

- **SwiftWhisper** (1.2.0+) — local Whisper model inference

## Common Tasks

- **Add a new setting:** Add property with didSet to AppSettings.swift, load in loadFromDefaults(), add UI in SettingsView.swift
- **Add a new LLM provider:** Create actor conforming to LLMClient, add case to LLMProvider enum, update makeLLMClient() factory in OllamaClient.swift
- **Add a new STT engine:** Create class conforming to STTEngine protocol, add case to STTProvider enum
- **Add a new integration:** Create client in Integrations/, add settings fields, wire into RecordingSession.stopRecording()
- **Add a new detail tab:** Add tag to Picker in MeetingDetailView.detailHeader, add case to tabContent switch, add Cmd+N shortcut in background group

## Product Vision

- Replacement for Granola app
- Menu bar icon with dropdown: upcoming meetings, join button, liquid glass transparency
- Proactive meeting reminders (5 min before)
- Meeting memory: remember past agreements, surface via Apple Reminders
- Action item creation: ClickUp/Linear tickets, Notion docs
- N8N integration for orchestration
- Window app is a MUST HAVE for querying past meetings

## UI Preferences

- Minimalist design with liquid glass transparency
- Dark mode support (system settings)
- Resizable sidebar
- "Ask anything" search bar for AI queries about meetings
