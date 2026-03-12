import SwiftUI

struct MeetingChatView: View {
    let meeting: Meeting
    @Environment(AppSettings.self) private var settings
    @Environment(MeetingQueryService.self) private var queryService

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isQuerying = false
    @State private var errorMessage: String?
    @State private var selectedModel: String = ""

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        let sourceMeetings: [String]
        let confidence: ChatBarMessage.GroundingConfidence?

        enum Role {
            case user
            case assistant
        }

        init(
            role: Role,
            text: String,
            sourceMeetings: [String] = [],
            confidence: ChatBarMessage.GroundingConfidence? = nil
        ) {
            self.role = role
            self.text = text
            self.sourceMeetings = sourceMeetings
            self.confidence = confidence
        }
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
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Ask a question about this meeting")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if isQuerying {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        .padding(.horizontal)
                        .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isQuerying) { _, querying in
                if querying {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(message.role == .user ? .blue : .green)

            Text(message.text)
                .font(.body)
                .textSelection(.enabled)

            if let confidence = message.confidence {
                confidenceBadge(confidence)
            }

            if !message.sourceMeetings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(message.sourceMeetings, id: \.self) { title in
                            Label(title, systemImage: "doc.text")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this meeting...", text: $inputText)
                .textFieldStyle(.plain)
                .onSubmit(submitQuery)
                .disabled(isQuerying)

            if !settings.availableModels.isEmpty {
                Picker("", selection: $selectedModel) {
                    Text("Default").tag("")
                    ForEach(settings.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
                .labelsHidden()
            }

            if isQuerying {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: submitQuery) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func submitQuery() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isQuerying else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isQuerying = true

        // Build chat history from previous messages (for multi-turn context)
        let history: [LLMChatMessage] = messages.dropLast().map { msg in
            LLMChatMessage(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.text
            )
        }

        Task {
            do {
                let answer = try await queryService.askAboutMeeting(
                    trimmed,
                    chatHistory: history,
                    meeting: meeting,
                    settings: settings,
                    modelOverride: selectedModel.isEmpty ? nil : selectedModel
                )
                let normalized = answer.lowercased()
                let confidence: ChatBarMessage.GroundingConfidence = {
                    if normalized.contains("[error:")
                        || normalized.contains("insufficient evidence")
                        || normalized.contains("not enough information")
                        || normalized.contains("don't have enough") {
                        return .low
                    }
                    return .high
                }()
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: answer,
                        sourceMeetings: [meeting.title.isEmpty ? "Untitled Meeting" : meeting.title],
                        confidence: confidence
                    )
                )
            } catch {
                errorMessage = error.localizedDescription
                messages.append(ChatMessage(role: .assistant, text: "Error: \(error.localizedDescription)"))
            }
            isQuerying = false
        }
    }

    private func confidenceBadge(_ confidence: ChatBarMessage.GroundingConfidence) -> some View {
        let color: Color
        switch confidence {
        case .low:
            color = .orange
        case .medium:
            color = .yellow
        case .high:
            color = .green
        }

        return Label(confidence.displayLabel, systemImage: "checkmark.seal")
            .font(.caption)
            .foregroundStyle(color)
    }
}
