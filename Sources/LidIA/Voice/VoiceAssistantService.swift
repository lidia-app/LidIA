import Foundation
import SwiftData
import os

@MainActor
@Observable
final class VoiceAssistantService {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "VoiceAssistant")

    let inputController = VoiceInputController()

    /// Conversation history for multi-turn dialogue.
    private(set) var conversationHistory: [LLMChatMessage] = []

    /// Whether voice mode is active (persists across turns).
    private(set) var isActive = false

    /// Partial transcript text for display (unconfirmed tokens).
    var partialText = ""

    private var settings: AppSettings?
    private var modelManager: ModelManager?
    private var ttsModelManager: TTSModelManager?
    private var queryService: MeetingQueryService?
    private var backgroundContext: ModelContext?
    private var currentTask: Task<Void, Never>?
    private var activePipeline: (any VoicePipeline)?
    private let playbackQueue = AudioPlaybackQueue()
    private var contextCache: VoiceMeetingContextCache?

    private static let systemPrompt = """
        You are LidIA, a voice assistant for meeting notes and productivity. \
        You are speaking out loud — be extremely brief. \
        For action requests (create, complete, edit, delete), just confirm and stop. \
        For questions, answer in 1-2 sentences max. \
        No filler, no elaboration, no follow-up questions unless truly ambiguous. \
        No markdown, no emojis.

        \(VoiceToolExecutor.toolPrompt)
        """

    func configure(settings: AppSettings, modelManager: ModelManager, ttsModelManager: TTSModelManager,
                   queryService: MeetingQueryService, backgroundContext: ModelContext) {
        self.settings = settings
        self.modelManager = modelManager
        self.ttsModelManager = ttsModelManager
        self.queryService = queryService
        self.backgroundContext = backgroundContext
        self.contextCache = VoiceMeetingContextCache(modelContext: backgroundContext)

        inputController.applyHotkeyString(settings.voiceHotkey)
        inputController.silenceDuration = settings.voiceSilenceTimeout
        if settings.voiceEnabled {
            inputController.registerHotkey()
        }
    }

    func reconfigure() {
        guard let settings else { return }
        inputController.applyHotkeyString(settings.voiceHotkey)
        inputController.silenceDuration = settings.voiceSilenceTimeout
        if settings.voiceEnabled {
            inputController.unregisterHotkey()
            inputController.registerHotkey()
        } else {
            inputController.unregisterHotkey()
            endSession()
        }
    }

    /// Toggle voice mode on/off. Called from toolbar button or hotkey.
    func toggle() {
        Self.logger.info("toggle() called — isActive=\(self.isActive), settings=\(self.settings != nil ? "set" : "nil"), modelManager=\(self.modelManager != nil ? "set" : "nil")")
        if isActive {
            endSession()
        } else {
            if settings == nil {
                Self.logger.error("Voice toggle called before configure() — ignoring")
                return
            }
            startSession()
        }
    }

    /// Begin a voice mode session. Orb appears, mic starts listening.
    func startSession() {
        guard !isActive else { return }

        guard let settings else {
            Self.logger.error("Cannot start voice session: settings not configured. Call configure() first.")
            return
        }
        guard let modelManager else {
            Self.logger.error("Cannot start voice session: modelManager not configured. Call configure() first.")
            return
        }

        isActive = true
        Self.logger.info("startSession() — isActive set to true, building pipeline...")
        conversationHistory = [
            LLMChatMessage(role: "system", content: """
                \(Self.systemPrompt)

                Today's date is \(Date.now.formatted(date: .complete, time: .omitted)).
                """)
        ]
        activePipeline = buildPipeline(settings: settings, modelManager: modelManager)
        Task { await activePipeline?.warmup() }
        startListeningTurn()
    }

    /// End voice mode entirely.
    func endSession() {
        isActive = false
        currentTask?.cancel()
        currentTask = nil

        // Capture pipeline before nilling so we can unload its models
        let pipeline = activePipeline
        activePipeline?.cancel()
        activePipeline = nil

        playbackQueue.stop()
        inputController.setIdle()
        conversationHistory = []
        partialText = ""
        contextCache?.invalidateContextOnly()

        // Unload TTS/STT models to free memory after voice session ends
        if let local = pipeline as? LocalVoicePipeline {
            Task {
                await local.unloadModels()
                Self.logger.info("Voice models unloaded")
            }
        }
    }

    /// Start a new listening turn within an active session.
    private func startListeningTurn() {
        guard isActive else { return }
        inputController.startListening()
    }

    /// Called when silence is detected or user explicitly ends their turn.
    func onUserFinishedSpeaking() {
        guard isActive, inputController.state == .listening else { return }
        currentTask = Task {
            await processTurn()
        }
    }

    /// Manually submit current input (tap orb to send).
    func submitCurrentInput() {
        onUserFinishedSpeaking()
    }

    // MARK: - Pipeline Coordination

    private func processTurn() async {
        guard let pipeline = activePipeline else { return }

        let samples = inputController.stopListening()
        guard !samples.isEmpty else {
            startListeningTurn()
            return
        }

        let contextProvider: @Sendable (String) async -> String = { [weak self] transcript in
            await MainActor.run { self?.buildEnrichedPrompt(for: transcript) ?? "" }
        }

        let input = VoiceTurnInput(
            audioSamples: samples,
            sampleRate: 48000,
            conversationHistory: conversationHistory,
            baseSystemPrompt: buildBaseSystemPrompt(),
            contextProvider: contextProvider
        )

        inputController.setThinking()
        partialText = ""

        for await event in pipeline.process(turn: input) {
            switch event {
            case .partialTranscript(let partial):
                partialText = partial
            case .transcribed(let text):
                inputController.transcribedText = text
                partialText = ""
            case .responseChunk(let token):
                inputController.responseText += token
            case .responseComplete(let text):
                inputController.responseText = text
                conversationHistory.append(LLMChatMessage(role: "user", content: inputController.transcribedText))
                conversationHistory.append(LLMChatMessage(role: "assistant", content: text))
            case .audioReady(let data):
                inputController.setSpeaking()
                playbackQueue.enqueue(data)
            case .toolResult(let info):
                Self.logger.info("Tool result: \(info)")
            case .error(let msg):
                Self.logger.error("Pipeline error: \(msg)")
            case .finished:
                break
            }
        }

        // Wait for any queued audio to finish playing
        await playbackQueue.waitUntilDrained()

        guard !Task.isCancelled, isActive else { return }
        inputController.responseText = ""
        startListeningTurn()
    }

    // MARK: - Context Building

    private func buildBaseSystemPrompt() -> String {
        let personalization = settings.map { VoiceToolExecutor.personalizationPrompt(settings: $0) } ?? ""
        return """
            \(Self.systemPrompt)

            \(personalization)

            Today's date is \(Date.now.formatted(date: .complete, time: .omitted)).
            """
    }

    private func buildEnrichedPrompt(for transcript: String) -> String {
        let meetingContext = fetchMeetingContext(for: transcript)
        var prompt = buildBaseSystemPrompt()
        if !meetingContext.isEmpty {
            prompt += """

                The user's meeting data (use this to answer questions about their meetings, \
                action items, decisions, and attendees):

                \(meetingContext)
                """
        }
        return prompt
    }

    private func fetchMeetingContext(for query: String) -> String {
        contextCache?.meetingContext(for: query) ?? ""
    }

    // MARK: - Pipeline Factory

    private func buildPipeline(settings: AppSettings, modelManager: ModelManager) -> any VoicePipeline {
        let backend = VoiceAssistantBackend.resolve(
            ttsProvider: settings.ttsProvider,
            openAIAPIKey: settings.openaiAPIKey
        )

        switch backend {
        case .openAIRealtime:
            let voice = settings.ttsVoiceID.isEmpty ? "nova" : settings.ttsVoiceID
            return RealtimeVoicePipeline(apiKey: settings.openaiAPIKey, voice: voice)
        case .localPipeline:
            let stt = ParakeetEngine()
            let (llm, model) = voiceLLM(settings: settings, modelManager: modelManager)
            let tts = makeTTSEngine(settings: settings)
            let fallback = SystemTTSEngine()
            let toolConfig = VoiceToolExecutor.Configuration(modelContext: backgroundContext)
            return LocalVoicePipeline(
                stt: stt, llm: llm, model: model,
                tts: tts, fallbackTTS: fallback, toolConfig: toolConfig
            )
        }
    }

    private func makeTTSEngine(settings: AppSettings) -> any TTSEngine {
        switch settings.ttsProvider {
        case .mlx:
            #if os(macOS)
            if let ttsModelManager {
                let modelID = settings.selectedTTSModelID.isEmpty
                    ? ttsModelManager.downloadedModelIDs.first
                    : (ttsModelManager.downloadedModelIDs.contains(settings.selectedTTSModelID)
                       ? settings.selectedTTSModelID : ttsModelManager.downloadedModelIDs.first)
                if let modelID {
                    return MLXTTSEngine(modelRepo: modelID)
                }
            }
            #endif
            Self.logger.warning("MLX TTS requested but no model available — falling back to system voice")
            return SystemTTSEngine(voiceIdentifier: settings.ttsVoiceID.isEmpty ? nil : settings.ttsVoiceID)

        case .openai:
            if !settings.openaiAPIKey.isEmpty {
                return OpenAITTSEngine(
                    apiKey: settings.openaiAPIKey,
                    voice: settings.ttsVoiceID.isEmpty ? "nova" : settings.ttsVoiceID
                )
            }
            Self.logger.warning("OpenAI TTS requested but no API key — falling back to system voice")
            return SystemTTSEngine(voiceIdentifier: settings.ttsVoiceID.isEmpty ? nil : settings.ttsVoiceID)

        case .system:
            return SystemTTSEngine(voiceIdentifier: settings.ttsVoiceID.isEmpty ? nil : settings.ttsVoiceID)

        case .automatic:
            // Cascade: MLX (if downloaded) → OpenAI (if key) → System
            #if os(macOS)
            if let ttsModelManager, ttsModelManager.isTTSModelAvailable {
                let modelID = settings.selectedTTSModelID.isEmpty
                    ? ttsModelManager.downloadedModelIDs.first
                    : (ttsModelManager.downloadedModelIDs.contains(settings.selectedTTSModelID)
                       ? settings.selectedTTSModelID : ttsModelManager.downloadedModelIDs.first)
                if let modelID {
                    return MLXTTSEngine(modelRepo: modelID)
                }
            }
            #endif
            if !settings.openaiAPIKey.isEmpty {
                return OpenAITTSEngine(
                    apiKey: settings.openaiAPIKey,
                    voice: settings.ttsVoiceID.isEmpty ? "nova" : settings.ttsVoiceID
                )
            }
            Self.logger.info("Automatic TTS: no MLX models or OpenAI key — using system voice")
            return SystemTTSEngine(voiceIdentifier: settings.ttsVoiceID.isEmpty ? nil : settings.ttsVoiceID)
        }
    }

    private func voiceLLM(settings: AppSettings, modelManager: ModelManager) -> (any LLMClient, String) {
        if settings.llmProvider == .mlx {
            let client = MLXLocalClient(modelManager: modelManager)
            let model = effectiveModel(for: .query, settings: settings, taskType: .chat)
            return (client, model)
        }

        let hasAPIKey = !settings.openaiAPIKey.isEmpty || !settings.anthropicAPIKey.isEmpty
        if !hasAPIKey && !modelManager.downloadedModels.isEmpty {
            let client = MLXLocalClient(modelManager: modelManager)
            let model = settings.selectedMLXModelID.isEmpty
                ? (modelManager.downloadedModels.first?.id ?? "")
                : settings.selectedMLXModelID
            return (client, model)
        }

        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
        let model = effectiveModel(for: .query, settings: settings, taskType: .chat)
        return (client, model)
    }

    func teardown() {
        endSession()
        inputController.unregisterHotkey()
    }
}

