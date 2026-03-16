import SwiftUI
import SwiftData
import LidIAKit

struct ChatTab: View {
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
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        messageBubble(msg)
                    }

                    if isStreaming && !currentStreamText.isEmpty {
                        messageBubble(ChatMsg(role: .assistant, text: currentStreamText))
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
        }
    }

    private func messageBubble(_ msg: ChatMsg) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 60) }

            Text(msg.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    msg.role == .user
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 16)
                )

            if msg.role == .assistant { Spacer(minLength: 60) }
        }
        .id(msg.id)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about meetings...", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.blue)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        messages.append(ChatMsg(role: .user, text: text))
        inputText = ""
        isStreaming = true
        currentStreamText = ""

        streamTask = Task {
            defer { isStreaming = false }

            // Build context from recent meetings
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let recentMeetings = (try? modelContext.fetch(descriptor))?.prefix(5) ?? []
            let context = recentMeetings.map { meeting in
                "Meeting: \(meeting.title) (\(meeting.date.formatted()))\nSummary: \(meeting.summary.prefix(300))"
            }.joined(separator: "\n\n")

            let systemPrompt = """
                You are LidIA, a meeting intelligence assistant. Answer questions about the user's meetings based on the context below.
                Be concise and helpful. If you don't have enough context, say so.

                Recent meetings:
                \(context)
                """

            guard !settings.openaiAPIKey.isEmpty else {
                messages.append(ChatMsg(role: .assistant, text: "Please add your OpenAI API key in Settings to use chat."))
                return
            }

            do {
                let apiMessages: [[String: String]] = [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": text],
                ]

                // Simple OpenAI chat completion (non-streaming for simplicity)
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(settings.openaiAPIKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "model": "gpt-4o-mini",
                    "messages": apiMessages,
                    "max_tokens": 1024,
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, _) = try await URLSession.shared.data(for: request)

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: String],
                   let content = message["content"] {
                    messages.append(ChatMsg(role: .assistant, text: content))
                } else {
                    messages.append(ChatMsg(role: .assistant, text: "Sorry, I couldn't process that request."))
                }
            } catch {
                messages.append(ChatMsg(role: .assistant, text: "Error: \(error.localizedDescription)"))
            }
        }
    }
}
