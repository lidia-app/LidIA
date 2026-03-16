import SwiftUI
import SwiftData

@MainActor
@Observable
final class ChatBarViewModel {

    // MARK: - Suggestion Type

    struct Suggestion: Identifiable {
        let id = UUID()
        let text: String
        let icon: String
    }

    // MARK: - Context Scope

    enum ContextScope: String, CaseIterable, Codable, Sendable {
        case selectedMeeting = "Selected meeting"
        case allMeetings = "All meetings"
        case myNotes = "My notes"
    }

    // MARK: - Thread (value type for views)

    struct ChatThread: Identifiable, Codable, Sendable {
        let id: UUID
        var title: String
        var scope: ContextScope
        let createdAt: Date
        var updatedAt: Date
        var messages: [ChatBarMessage]

        init(
            id: UUID = UUID(),
            title: String,
            scope: ContextScope,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            messages: [ChatBarMessage] = []
        ) {
            self.id = id
            self.title = title
            self.scope = scope
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.messages = messages
        }
    }

    // MARK: - Recording State

    enum RecordingState {
        case idle
        case recording
        case justFinished
    }

    // MARK: - Services

    let dictationService = DictationService()
    let threadStore = ChatThreadStore()
    let contextBuilder = MeetingContextBuilder()

    // MARK: - Chat State

    var messages: [ChatBarMessage] = []
    var inputText = ""
    var isStreaming = false
    var currentStreamingText = ""

    var pendingAttachments: [FileAttachment] = []

    // Empty string = auto (ModelRouter decides)
    var modelOverride = ""
    var contextScope: ContextScope = .allMeetings
    var recordingState: RecordingState = .idle

    // MARK: - Forwarded Properties

    var isDictating: Bool { dictationService.isDictating }

    var threads: [ChatThread] {
        get { threadStore.threads }
        set { threadStore.threads = newValue }
    }

    var activeThreadID: UUID? {
        get { threadStore.activeThreadID }
        set { threadStore.activeThreadID = newValue }
    }

    var recentThreads: [ChatThread] {
        threadStore.recentThreads
    }

    // MARK: - Dependencies

    private var chatStream: (any ChatStream)?
    private var settings: AppSettings?
    private var backgroundContext: ModelContext?
    private var modelManager: ModelManager?
    private var streamTask: Task<Void, Never>?

    // MARK: - Configuration

    func configure(settings: AppSettings, modelContext: ModelContext, modelManager: ModelManager? = nil, backgroundContext: ModelContext? = nil) {
        self.settings = settings
        self.modelManager = modelManager
        self.backgroundContext = backgroundContext
        self.chatStream = makeChatStream(settings: settings)
        contextBuilder.configure(modelContext: modelContext)

        // Use background context for chat thread persistence if available
        threadStore.configure(modelContext: backgroundContext ?? modelContext)

        // Wire dictation callback
        dictationService.onTranscription = { [weak self] transcript in
            guard let self else { return }
            if self.inputText.isEmpty {
                self.inputText = transcript
            } else {
                self.inputText += " " + transcript
            }
        }
    }

    func updateSelectedMeeting(_ meeting: Meeting?) {
        contextBuilder.updateSelectedMeeting(meeting)
    }

    // MARK: - Dictation (forwarded)

    func toggleDictation() {
        dictationService.toggleDictation()
    }

    // MARK: - Thread Operations (forwarded)

    func openThread(_ thread: ChatThread) {
        messages = threadStore.openThread(thread)
        contextScope = thread.scope
        inputText = ""
        pendingAttachments = []
        currentStreamingText = ""
    }

    func openThread(id: UUID) {
        guard let msgs = threadStore.openThread(id: id) else { return }
        if let thread = threadStore.threads.first(where: { $0.id == id }) {
            messages = msgs
            contextScope = thread.scope
            inputText = ""
            pendingAttachments = []
            currentStreamingText = ""
        }
    }

    func startNewThread(scope: ContextScope? = nil) {
        streamTask?.cancel()
        streamTask = nil
        threadStore.startNewThread()
        messages = []
        inputText = ""
        pendingAttachments = []
        currentStreamingText = ""
        isStreaming = false

        if let scope {
            contextScope = scope
        }
    }

    func deleteThread(_ thread: ChatThread) {
        threadStore.deleteThread(thread)
        if activeThreadID == nil {
            startNewThread(scope: contextScope)
        }
    }

    static func makeThreadTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "New chat"
        }

        let words = trimmed.split(separator: " ")
        let headline = words.prefix(8).joined(separator: " ")
        return String(headline)
    }

    // MARK: - Suggestions

    var suggestions: [Suggestion] {
        guard messages.isEmpty, !isStreaming else { return [] }

        switch recordingState {
        case .idle:
            let hasMeetings = (try? contextBuilder.fetchMeetings(limit: 1, includeInProgress: false))?.isEmpty == false
            if hasMeetings {
                return [
                    Suggestion(text: "Summarize this week", icon: "calendar"),
                    Suggestion(text: "Open action items", icon: "checklist"),
                    Suggestion(text: "What did I miss?", icon: "questionmark.bubble"),
                    Suggestion(text: "Draft follow-up email", icon: "envelope"),
                ]
            }
            return [Suggestion(text: "Record your first meeting", icon: "mic.fill")]

        case .recording:
            return [
                Suggestion(text: "Summarize so far", icon: "text.badge.star"),
                Suggestion(text: "Key decisions", icon: "lightbulb"),
                Suggestion(text: "What did I miss?", icon: "questionmark.bubble"),
            ]

        case .justFinished:
            return [
                Suggestion(text: "Generate action items", icon: "checklist"),
                Suggestion(text: "Create title", icon: "textformat"),
                Suggestion(text: "Draft meeting recap", icon: "doc.text"),
            ]
        }
    }

    // MARK: - Send Message

    func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        guard let settings, let chatStream else { return }

        if recordingState == .justFinished {
            recordingState = .idle
        }

        threadStore.ensureActiveThreadExists(initialPrompt: trimmed, scope: contextScope)

        let userMessage = ChatBarMessage(
            role: .user,
            text: trimmed,
            attachments: pendingAttachments
        )
        messages.append(userMessage)

        let attachments = pendingAttachments
        inputText = ""
        pendingAttachments = []

        let selectedModel: String
        if modelOverride.isEmpty {
            selectedModel = ModelRouter.route(query: trimmed, settings: settings)
        } else {
            selectedModel = modelOverride
        }

        let contextBundle = contextBuilder.buildContextBundle(for: trimmed, scope: contextScope)
        if !contextBundle.hasEvidence && attachments.isEmpty {
            messages.append(
                ChatBarMessage(
                    role: .assistant,
                    text: "Insufficient evidence: no meetings are available in this scope yet.",
                    groundingConfidence: .low
                )
            )
            threadStore.syncActiveThread(messages: messages, scope: contextScope)
            return
        }
        let history: [LLMChatMessage] = messages.dropLast().map { msg in
            LLMChatMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.text
            )
        }

        threadStore.syncActiveThread(messages: messages, scope: contextScope)

        isStreaming = true
        currentStreamingText = ""

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isStreaming = false
            }

            let stream = chatStream.send(
                trimmed,
                history: history,
                context: contextBundle.contextText,
                attachments: attachments,
                model: selectedModel
            )

            for await token in stream {
                if Task.isCancelled { return }
                self.currentStreamingText += token
            }

            if Task.isCancelled { return }

            let rawText = self.currentStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawText.isEmpty {
                let toolResult: VoiceToolExecutor.Result
                if let ctx = self.backgroundContext {
                    toolResult = VoiceToolExecutor.process(response: rawText, modelContext: ctx)
                } else {
                    // Strip tool markers even without a context for execution
                    let cleaned = VoiceToolExecutor.stripToolMarkers(rawText)
                    toolResult = VoiceToolExecutor.Result(spokenResponse: cleaned, executedActions: [])
                }

                let finalText = toolResult.spokenResponse
                let sourceTitles = self.contextBuilder.deriveSourceTitles(
                    answer: finalText,
                    candidateTitles: contextBundle.candidateSourceTitles
                )
                let confidence = self.contextBuilder.deriveGroundingConfidence(
                    answer: finalText,
                    sourceCount: sourceTitles.count
                )
                self.messages.append(
                    ChatBarMessage(
                        role: .assistant,
                        text: finalText,
                        sourceMeetings: sourceTitles,
                        groundingConfidence: confidence
                    )
                )
                self.threadStore.syncActiveThread(messages: self.messages, scope: self.contextScope)
            }

            self.currentStreamingText = ""
        }
    }

    // MARK: - Attachments

    func addAttachment(url: URL) {
        let name = url.lastPathComponent
        let content: String

        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                content = String(text.prefix(10_000))
            } else {
                content = "[Binary file: \(name), \(data.count) bytes]"
            }
        } catch {
            content = "[Could not read file: \(error.localizedDescription)]"
        }

        pendingAttachments.append(FileAttachment(name: name, content: content))
    }

    func removeAttachment(_ attachment: FileAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Retry

    /// Retry the last assistant response by removing it and re-sending the preceding user message.
    func retry(messageID: UUID) {
        guard !isStreaming else { return }
        // Find the message index
        guard let idx = messages.firstIndex(where: { $0.id == messageID }),
              messages[idx].role == .assistant else { return }
        // Find the preceding user message
        let userIdx = messages[..<idx].lastIndex(where: { $0.role == .user })
        guard let uIdx = userIdx else { return }
        let userText = messages[uIdx].text
        // Remove the assistant response
        messages.remove(at: idx)
        // Re-send
        inputText = userText
        send()
    }

    // MARK: - Conversation Management

    func clearConversation() {
        startNewThread(scope: contextScope)
    }

    // MARK: - Private: Chat Stream Factory

    private func makeChatStream(settings: AppSettings) -> any ChatStream {
        if settings.llmProvider == .openai, !settings.openaiAPIKey.isEmpty {
            let model = settings.openaiModel.isEmpty
                ? ModelMenuCatalog.autoModel(for: .openai, availableModels: settings.availableModels)
                : settings.openaiModel
            return OpenAIWebSocketStream(apiKey: settings.openaiAPIKey, defaultModel: model)
        }
        return HTTPChatStream(settings: settings, modelManager: modelManager)
    }
}
