import SwiftUI

struct ChatPopupView: View {
    @Bindable var viewModel: ChatBarViewModel
    @FocusState private var inputFocused: Bool

    var onClose: () -> Void
    var onGoFullscreen: () -> Void

    private var hasInput: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            messageList
            Divider().opacity(0.3)
            inputRow
        }
        .frame(maxWidth: 520)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassPill(cornerRadius: 16, shadowColor: .black.opacity(0.18), shadowRadius: 20, shadowY: -4)
        .onAppear { inputFocused = true }
        .onExitCommand { onClose() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Chat")
                .font(.subheadline.weight(.semibold))

            Spacer()

            headerButton(icon: "arrow.up.left.and.arrow.down.right", help: "Full screen") {
                onGoFullscreen()
            }
            headerButton(icon: "xmark", help: "Close (Esc)") {
                onClose()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func headerButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty && !viewModel.isStreaming {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                onRetry: message.role == .assistant ? {
                                    viewModel.retry(messageID: message.id)
                                } : nil,
                                onRetryWith: message.role == .assistant ? { provider in
                                    viewModel.retryWith(messageID: message.id, provider: provider)
                                } : nil
                            )
                                .id(message.id)
                        }

                        if viewModel.isStreaming {
                            streamingBubble
                                .id("streaming")
                        }
                    }
                    .padding(14)
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.currentStreamingText) {
                if viewModel.isStreaming {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Ask anything about your meetings")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !viewModel.suggestions.isEmpty {
                VStack(spacing: 4) {
                    ForEach(viewModel.suggestions.prefix(3)) { suggestion in
                        Button {
                            viewModel.inputText = suggestion.text
                            viewModel.send()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: suggestion.icon)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(suggestion.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    // MARK: - Bubbles

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 6) {
            if viewModel.currentStreamingText.isEmpty {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                MarkdownBlockView(text: viewModel.currentStreamingText)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 6) {
            TextField("Follow up...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($inputFocused)
                .onSubmit { viewModel.send() }

            ChatSendButton(isActive: hasInput, iconSize: 11, frameSize: 24) {
                viewModel.send()
            }
            .disabled(!hasInput || viewModel.isStreaming)

            if viewModel.isStreaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
