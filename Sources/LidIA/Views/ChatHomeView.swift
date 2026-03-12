import SwiftUI
import SwiftData

struct ChatHomeView: View {
    @Bindable var viewModel: ChatBarViewModel
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @FocusState private var inputFocused: Bool
    @State private var hoveredThreadID: UUID?

    /// When set, auto-navigates into this thread on appear (used by fullscreen from popup).
    var navigateToThreadID: UUID?
    /// Parent navigation path for pushing thread detail views.
    @Binding var path: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                Text("Ask anything")
                    .font(.largeTitle.bold())

                composer

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Chats")
                        .font(.headline)

                    if viewModel.recentThreads.isEmpty {
                        ContentUnavailableView(
                            "No chats yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Start a conversation above to create your first thread.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.recentThreads) { thread in
                                    Button {
                                        viewModel.openThread(thread)
                                        path.append(thread.id)
                                    } label: {
                                        threadRow(thread)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete Chat", role: .destructive) {
                                            viewModel.deleteThread(thread)
                                        }
                                    }

                                    Divider()
                                        .padding(.leading, 4)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(24)
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        viewModel.startNewThread()
                        inputFocused = true
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
            .onAppear {
                if let threadID = navigateToThreadID {
                    viewModel.openThread(id: threadID)
                    path.append(threadID)
                }
            }
    }

    private func sendNewChat() {
        guard hasInput else { return }
        let text = viewModel.inputText
        viewModel.startNewThread()
        viewModel.inputText = text
        viewModel.send()
        if let threadID = viewModel.activeThreadID {
            path.append(threadID)
        }
    }

    private var hasInput: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 6) {
                TextField("Ask about meetings, notes, or action items...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($inputFocused)
                    .onSubmit { sendNewChat() }
                    .frame(maxWidth: .infinity)

                // Send
                ChatSendButton(isActive: hasInput) {
                    sendNewChat()
                }
                .disabled(!hasInput || viewModel.isStreaming)

                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }

                // Scope pill
                Menu {
                    ForEach(ChatBarViewModel.ContextScope.allCases, id: \.self) { scope in
                        Button {
                            viewModel.contextScope = scope
                        } label: {
                            ChatHelpers.menuRow(scope.rawValue, selected: viewModel.contextScope == scope)
                        }
                    }
                } label: {
                    ChatPill(icon: "text.book.closed", text: ChatHelpers.scopeLabel(viewModel.contextScope))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Model pill
                ModelMenuView(
                    modelOverride: $viewModel.modelOverride,
                    availableModels: settings.availableModels,
                    llmProvider: settings.llmProvider
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPill()
    }

    private func threadRow(_ thread: ChatBarViewModel.ChatThread) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(thread.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(thread.scope.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastText = thread.messages.last?.text, !lastText.isEmpty {
                Text(lastText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .background {
            if hoveredThreadID == thread.id {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredThreadID = hovering ? thread.id : nil
            }
        }
    }
}
