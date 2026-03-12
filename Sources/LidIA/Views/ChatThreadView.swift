import SwiftUI

struct ChatThreadView: View {
    @Bindable var viewModel: ChatBarViewModel
    @Environment(AppSettings.self) private var settings
    @FocusState private var inputFocused: Bool
    let threadID: UUID
    let availableModels: [String]

    private var hasInput: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "text.bubble",
                    description: Text("Ask your first question below.")
                )
            } else {
                messageList
            }

            composer
                .padding(14)
        }
        .navigationTitle(viewModel.recentThreads.first(where: { $0.id == threadID })?.title ?? "Chat")
        .onAppear {
            viewModel.openThread(id: threadID)
        }
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 6) {
                TextField("Continue this chat...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($inputFocused)
                    .onSubmit { viewModel.send() }
                    .frame(maxWidth: .infinity)

                // Send
                ChatSendButton(isActive: hasInput) {
                    viewModel.send()
                }
                .disabled(!hasInput || viewModel.isStreaming)

                if viewModel.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }

                // Model pill
                ModelMenuView(
                    modelOverride: $viewModel.modelOverride,
                    availableModels: availableModels,
                    llmProvider: settings.llmProvider
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPill()
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isStreaming {
                        HStack(alignment: .top, spacing: 8) {
                            if viewModel.currentStreamingText.isEmpty {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .foregroundStyle(.tertiary)
                            } else {
                                MarkdownBlockView(text: viewModel.currentStreamingText)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("streaming")
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.currentStreamingText) {
                if viewModel.isStreaming {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }

}
