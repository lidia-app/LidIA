import SwiftUI
import SwiftData
import LidIAKit

struct iOSChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSSettings.self) private var settings

    @State private var messages: [ChatMsg] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var currentStreamText = ""
    @State private var streamTask: Task<Void, Never>?

    struct ChatMsg: Identifiable {
        let id = UUID()
        let role: Role
        var text: String

        enum Role { case user, assistant }
    }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider()
            inputBar
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            streamTask?.cancel()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Ask about your meetings")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                suggestionButton("Summarize this week", icon: "calendar")
                suggestionButton("Open action items", icon: "checklist")
                suggestionButton("What did I miss?", icon: "questionmark.bubble")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding()
    }

    private func suggestionButton(_ text: String, icon: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Label(text, systemImage: icon)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }

                    if isStreaming {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LidIA")
                                .font(.caption.bold())
                                .foregroundStyle(.green)

                            if currentStreamText.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Thinking...")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(currentStreamText)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("streaming")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: currentStreamText) {
                if isStreaming {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ msg: ChatMsg) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(msg.role == .user ? "You" : "LidIA")
                .font(.caption.bold())
                .foregroundStyle(msg.role == .user ? .blue : .green)

            Text(msg.text)
                .font(.body)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about meetings...", text: $inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .onSubmit(sendMessage)
                .disabled(isStreaming)

            if isStreaming {
                Button {
                    streamTask?.cancel()
                    streamTask = nil
                    isStreaming = false
                    if !currentStreamText.isEmpty {
                        messages.append(ChatMsg(role: .assistant, text: currentStreamText))
                        currentStreamText = ""
                    }
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Send

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        guard settings.hasAPIKey else {
            messages.append(ChatMsg(role: .user, text: trimmed))
            messages.append(ChatMsg(role: .assistant, text: "Please add your OpenAI API key in Settings first."))
            inputText = ""
            return
        }

        messages.append(ChatMsg(role: .user, text: trimmed))
        inputText = ""

        let context = buildContext(for: trimmed)
        let history = messages.dropLast().map { msg in
            LLMChatMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.text
            )
        }

        isStreaming = true
        currentStreamText = ""

        streamTask = Task { @MainActor in
            defer { isStreaming = false }

            let dateString = ISO8601DateFormatter.string(
                from: Date(), timeZone: .current,
                formatOptions: [.withFullDate]
            )
            let personalization = VoiceToolExecutor.personalizationPrompt(
                displayName: settings.displayName,
                personalityFragment: settings.personalityMode.promptFragment
            )

            let systemPrompt = """
                You are LidIA, an intelligent meeting assistant on iOS. Today is \(dateString).
                \(personalization)

                Meeting context:
                \(context)

                Grounding rules:
                - Base answers only on the provided meeting context.
                - If the context is insufficient, say so honestly.
                - Be concise — the user is on mobile.

                \(VoiceToolExecutor.toolPrompt)
                """

            var llmMessages: [LLMChatMessage] = [
                LLMChatMessage(role: "system", content: systemPrompt)
            ]
            llmMessages.append(contentsOf: history)
            llmMessages.append(LLMChatMessage(role: "user", content: trimmed))

            do {
                let stream = await streamOpenAI(messages: llmMessages, model: "gpt-4o-mini")
                for try await token in stream {
                    if Task.isCancelled { return }
                    currentStreamText += token
                }

                if Task.isCancelled { return }

                let raw = currentStreamText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    let result = VoiceToolExecutor.process(
                        response: raw,
                        modelContainer: modelContext.container
                    )
                    messages.append(ChatMsg(role: .assistant, text: result.spokenResponse))
                }
                currentStreamText = ""
            } catch {
                if !Task.isCancelled {
                    messages.append(ChatMsg(role: .assistant, text: "Error: \(error.localizedDescription)"))
                    currentStreamText = ""
                }
            }
        }
    }

    // MARK: - Context

    private func buildContext(for query: String) -> String {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let allMeetings = try? modelContext.fetch(descriptor) else {
            return "No meeting data available."
        }

        let completed = allMeetings.filter { $0.status == .complete }
        guard !completed.isEmpty else {
            return "No completed meetings yet."
        }

        let relevant = MeetingContextRetrievalService.relevantMeetings(
            for: query, from: completed, limit: 10
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var parts: [String] = []
        for meeting in relevant {
            var entry = "## \(meeting.title.isEmpty ? "Untitled" : meeting.title)"
            entry += "\nDate: \(formatter.string(from: meeting.date))"

            if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
                entry += "\nAttendees: \(attendees.joined(separator: ", "))"
            }

            let summary = MeetingContextRetrievalService.effectiveSummary(for: meeting)
            if !summary.isEmpty {
                entry += "\nSummary: \(summary)"
            }

            if !meeting.notes.isEmpty {
                entry += "\nNotes: \(String(meeting.notes.prefix(500)))"
            }

            if !meeting.actionItems.isEmpty {
                let items = meeting.actionItems.map { item in
                    "- [\(item.isCompleted ? "x" : " ")] \(item.title)"
                        + (item.assignee.map { " (@\($0))" } ?? "")
                }.joined(separator: "\n")
                entry += "\nAction Items:\n\(items)"
            }
            parts.append(entry)
        }

        return parts.isEmpty ? "No relevant meetings found." : parts.joined(separator: "\n\n")
    }

    // MARK: - OpenAI Streaming

    private func streamOpenAI(
        messages: [LLMChatMessage],
        model: String
    ) async -> AsyncThrowingStream<String, Error> {
        let apiKey = settings.openaiAPIKey
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        struct StreamRequest: Encodable {
            let model: String
            let messages: [LLMChatMessage]
            let stream: Bool
        }

        let body = StreamRequest(model: model, messages: messages, stream: true)
        request.httpBody = try? JSONEncoder().encode(body)

        struct StreamChunk: Decodable {
            let choices: [Choice]
            struct Choice: Decodable {
                let delta: Delta
                struct Delta: Decodable {
                    let content: String?
                }
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        continuation.finish(throwing: LLMError.httpError(
                            statusCode: http.statusCode,
                            message: "OpenAI API error"
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let content = chunk.choices.first?.delta.content,
                              !content.isEmpty else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
