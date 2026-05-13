import SwiftUI

struct ChatBarView: View {
    @Bindable var viewModel: ChatBarViewModel
    @Environment(RecordingSession.self) private var session
    @FocusState private var inputFocused: Bool
    var availableModels: [String]
    var provider: AppSettings.LLMProvider
    var onClose: (() -> Void)?
    @Binding var isExpanded: Bool

    /// Expands chat into the fullscreen workspace.
    var onExpandFullscreen: (() -> Void)?

    /// External trigger to focus the input field (toggled by Cmd+K).
    var focusTrigger: Binding<Bool>?

    @State private var showRecipeMenu = false

    private var hasInput: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 10) {
                // Expand to fullscreen workspace
                barPill(icon: "arrow.up.left.and.arrow.down.right") {
                    onExpandFullscreen?()
                }
                .help("Open chat workspace")

                // Input field
                TextField("Ask about meetings…", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($inputFocused)
                    .onSubmit {
                        viewModel.send()
                        onExpandFullscreen?()
                    }
                    .onChange(of: viewModel.inputText) { _, newValue in
                        if newValue == "/" {
                            showRecipeMenu = true
                        }
                    }
                    .popover(isPresented: $showRecipeMenu, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Insert recipe prompt — review and edit before sending.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                            ForEach(Recipe.builtIn) { recipe in
                                Button {
                                    viewModel.inputText = recipe.prompt
                                    showRecipeMenu = false
                                    inputFocused = true
                                } label: {
                                    HStack {
                                        Text(recipe.emoji)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(recipe.name)
                                                .font(.subheadline)
                                            Text(recipe.description)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .frame(width: 320)
                    }
                    .frame(maxWidth: .infinity)

                // Send button
                ChatSendButton(isActive: hasInput) {
                    viewModel.send()
                    onExpandFullscreen?()
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
                    availableModels: availableModels,
                    llmProvider: provider
                )

                // Mic
                barPill(icon: viewModel.isDictating ? "mic.fill" : "mic") {
                    viewModel.toggleDictation()
                }
                .help(viewModel.isDictating ? "Stop dictation" : "Voice input")
                .foregroundStyle(viewModel.isDictating ? .red : .secondary)

                // Close
                if onClose != nil {
                    Spacer().frame(width: 4)

                    barPill(icon: "xmark") {
                        onClose?()
                    }
                    .help("Hide Quick Chat")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 860)
        .glassPill(shadowColor: .black.opacity(0.15), shadowRadius: 16, shadowY: 6)
        .onChange(of: focusTrigger?.wrappedValue ?? false) { _, newValue in
            if newValue {
                inputFocused = true
                focusTrigger?.wrappedValue = false
            }
        }
    }

    // MARK: - Pill Components

    private func barPill(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }

}
