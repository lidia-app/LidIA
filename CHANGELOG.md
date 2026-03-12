# Changelog

All notable changes to LidIA will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-03-10

### Initial Public Release

#### Core Features
- Local-first meeting transcription using Parakeet STT (on-device, no cloud)
- Local LLM summarization via MLX (Apple Silicon optimized)
- Multi-provider LLM support: MLX, Ollama, OpenAI, Anthropic
- Meeting pipeline: transcribe, refine, summarize, extract action items
- Real-time live transcript during recording
- Floating transcript overlay panel

#### AI & Chat
- Conversational AI chat about meetings (popup + fullscreen)
- Voice assistant with orb UI and conversational mode
- Context-aware queries across meeting history
- Markdown rendering in chat responses
- Grounding confidence indicators with source attribution

#### Integrations
- Google Calendar (OAuth, event sync, meeting detection)
- Apple Calendar + Reminders (EventKit)
- Notion (meeting page export)
- N8N webhook automation

#### Meeting Intelligence
- Action item extraction and tracking with assignee detection
- People/relationship tracking across meetings
- Meeting prep with talking points
- Weekly digest service
- Proactive meeting reminders

#### UX
- Native macOS app with SwiftUI (liquid glass design)
- Menu bar icon with meeting controls
- Meeting detection banner (auto-detect active meetings)
- Granola-inspired floating chat bar with glass material
- Keyboard shortcuts (Cmd+1-5 tabs, Cmd+R record, Cmd+K chat)
- Spotlight indexing for meeting search

#### Export & Search
- Markdown export + clipboard
- Full-text search across meetings and people
- Spotlight integration
