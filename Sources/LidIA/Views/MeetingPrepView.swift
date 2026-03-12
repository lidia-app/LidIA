import SwiftUI
import SwiftData

struct MeetingPrepView: View {
    let event: EventKitManager.CalendarEvent
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var relationshipStore = RelationshipStore()
    @State private var rawContext: String = ""
    @State private var aiPrepNotes: String = ""
    @State private var isGenerating = false
    @State private var showSourceData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Prep: \(event.title)")
                    .font(.subheadline.bold())
                Spacer()
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // AI prep notes
            if !aiPrepNotes.isEmpty {
                MarkdownBlockView(text: aiPrepNotes)
                    .font(.caption)
            } else if rawContext.isEmpty {
                Text("No prior meetings with these attendees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !isGenerating {
                Text(rawContext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
            }

            // Source data disclosure
            if !rawContext.isEmpty {
                DisclosureGroup("Source Data", isExpanded: $showSourceData) {
                    Text(rawContext)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .onAppear {
            rawContext = relationshipStore.prepContext(
                for: event.attendees,
                modelContext: modelContext
            )
            if !rawContext.isEmpty {
                generatePrepNotes()
            }
        }
    }

    private func generatePrepNotes() {
        guard !isGenerating else { return }
        isGenerating = true
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let client = makeLLMClient(settings: settings, taskType: .chat)
                let model = effectiveModel(for: .query, settings: settings, taskType: .chat)
                guard !model.isEmpty else { return }

                let systemPrompt = """
                You are preparing briefing notes for an upcoming meeting. \
                ONLY reference information from the context provided below. \
                If you have no relevant context for an attendee, explicitly state \
                'No prior meeting history.' \
                NEVER invent past discussions, decisions, commitments, or relationships.

                Output format:
                For each attendee with history, provide:
                - Key open items and commitments
                - Last discussion topics
                - Your talking points for them

                Then provide a suggested agenda based on the open items and talking points.

                Be concise and actionable. Use bullet points.
                """

                let userPrompt = """
                Upcoming meeting: \(event.title)
                Attendees: \(event.attendees.joined(separator: ", "))

                Context from past meetings:
                \(rawContext)
                """

                let response = try await client.chat(
                    messages: [
                        LLMChatMessage(role: "system", content: systemPrompt),
                        LLMChatMessage(role: "user", content: userPrompt),
                    ],
                    model: model,
                    format: nil
                )
                aiPrepNotes = response
            } catch {
                // Silently fall back to raw context display
            }
        }
    }
}
