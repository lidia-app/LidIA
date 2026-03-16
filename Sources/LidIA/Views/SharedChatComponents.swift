import SwiftUI

// MARK: - GlassPillModifier

struct GlassPillModifier: ViewModifier {
    var cornerRadius: CGFloat = 22
    var shadowColor: Color = .black.opacity(0.08)
    var shadowRadius: CGFloat = 8
    var shadowX: CGFloat = 0
    var shadowY: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
    }
}

extension View {
    func glassPill(
        cornerRadius: CGFloat = 22,
        shadowColor: Color = .black.opacity(0.08),
        shadowRadius: CGFloat = 8,
        shadowX: CGFloat = 0,
        shadowY: CGFloat = 2
    ) -> some View {
        modifier(GlassPillModifier(
            cornerRadius: cornerRadius,
            shadowColor: shadowColor,
            shadowRadius: shadowRadius,
            shadowX: shadowX,
            shadowY: shadowY
        ))
    }
}

// MARK: - ChatSendButton

struct ChatSendButton: View {
    var isActive: Bool
    var iconSize: CGFloat = 12
    var frameSize: CGFloat = 28
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(isActive ? .white : .secondary)
                .frame(width: frameSize, height: frameSize)
                .background(in: Circle())
                .backgroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ChatPill

struct ChatPill: View {
    var icon: String
    var text: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            if let text {
                Text(text)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - ModelMenuView

struct ModelMenuView: View {
    @Binding var modelOverride: String
    let availableModels: [String]
    let llmProvider: AppSettings.LLMProvider
    @AppStorage("chat.showAdvancedModels") private var showAdvancedModels = false

    private var modelOptions: [String] {
        showAdvancedModels
            ? availableModels
            : ModelMenuCatalog.curatedModels(for: llmProvider, availableModels: availableModels)
    }

    private var modelLabel: String {
        modelOverride.isEmpty ? "Auto" : modelOverride
    }

    var body: some View {
        Menu {
            Button {
                modelOverride = ""
            } label: {
                ChatHelpers.menuRow("Auto", selected: modelOverride.isEmpty)
            }

            if !modelOptions.isEmpty {
                Divider()
            }

            ForEach(modelOptions, id: \.self) { model in
                Button {
                    modelOverride = model
                } label: {
                    ChatHelpers.menuRow(model, selected: modelOverride == model)
                }
            }

            Divider()

            Button(showAdvancedModels ? "Hide Advanced Models" : "Advanced\u{2026}") {
                showAdvancedModels.toggle()
            }
        } label: {
            ChatPill(icon: "cpu", text: modelLabel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - MessageBubbleView

struct MessageBubbleView: View {
    let message: ChatBarMessage
    var onRetry: (() -> Void)?

    var body: some View {
        if message.role == .user {
            Text(message.text)
                .font(.subheadline)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(.accentColor), in: .rect(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MarkdownBlockView(text: message.text)
                    .font(.subheadline)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let confidence = message.groundingConfidence {
                        ConfidenceBadgeView(confidence: confidence)
                    }

                    if let onRetry {
                        Button {
                            onRetry()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Retry this response")
                    }
                }

                if !message.sourceMeetings.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(message.sourceMeetings, id: \.self) { title in
                                Text(title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .glassEffect(.regular, in: .capsule)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - ConfidenceBadgeView

struct ConfidenceBadgeView: View {
    let confidence: ChatBarMessage.GroundingConfidence

    private var color: Color {
        switch confidence {
        case .low: .orange
        case .medium: .yellow
        case .high: .green
        }
    }

    var body: some View {
        Label(confidence.displayLabel, systemImage: "checkmark.seal")
            .font(.caption2)
            .foregroundStyle(color)
    }
}

// MARK: - ChatHelpers

enum ChatHelpers {
    static func menuRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    static func scopeLabel(_ scope: ChatBarViewModel.ContextScope) -> String {
        switch scope {
        case .selectedMeeting: "Meeting"
        case .allMeetings: "All"
        case .myNotes: "Notes"
        }
    }
}

