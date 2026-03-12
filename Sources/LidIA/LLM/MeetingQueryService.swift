import SwiftUI
import SwiftData

@MainActor
@Observable
final class MeetingQueryService {
    var isQuerying = false
    var lastResponse: QueryResponse?
    var error: String?
    var modelManager: ModelManager?

    struct QueryResponse {
        let answer: String
        let sourceMeetings: [Meeting]
    }

    /// Query all meetings with natural language
    func query(_ text: String, modelContext: ModelContext, settings: AppSettings, modelOverride: String? = nil) async {
        isQuerying = true
        error = nil
        lastResponse = nil

        do {
            // Fetch all meetings and filter to completed ones in Swift
            // (SwiftData #Predicate doesn't reliably support raw-representable enums)
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let allMeetings = try modelContext.fetch(descriptor)
            let meetings = allMeetings.filter { $0.status == .complete }

            guard !meetings.isEmpty else {
                self.error = "No completed meetings to search."
                isQuerying = false
                return
            }

            // Build context from pre-filtered meetings (recency + attendee/topic overlap).
            let expandedKeywords = ["last week", "this month", "all my", "every", "action items", "what did i promise"]
            let expandedSearch = expandedKeywords.contains(where: { text.lowercased().contains($0) })
            let selected = MeetingContextRetrievalService.relevantMeetings(
                for: text,
                from: meetings,
                limit: expandedSearch ? 50 : 20
            )
            let context = buildContext(from: selected, limit: expandedSearch ? 50 : 20)

            let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
            let model = modelOverride.flatMap({ $0.isEmpty ? nil : $0 }) ?? effectiveModel(for: .query, settings: settings, taskType: .chat)
            let content = try await client.chat(
                messages: [
                    .init(role: "system", content: """
                        You are a meeting intelligence assistant. Answer questions about the user's meetings \
                        based on the following meeting data. You understand:
                        - Time filters: "last week", "this month", "in January", "past 30 days"
                        - Person filters: "with Sarah", "meetings with the engineering team"
                        - Topic filters: "about pricing", "regarding the API"
                        - Action item queries: "my action items", "what did I promise", "overdue tasks"

                        Be specific and reference meeting titles, dates, and attendees when relevant. \
                        Format action items as bullet lists. If the information isn't in the data, say so.

                        Today's date is \(Date.now.formatted(date: .complete, time: .omitted)).

                        Meeting data:
                        \(context)
                        """),
                    .init(role: "user", content: text),
                ],
                model: model,
                format: nil
            )

            // Determine which meetings were referenced in the answer
            let referenced = selected.filter { meeting in
                content.localizedCaseInsensitiveContains(meeting.title)
            }

            lastResponse = QueryResponse(
                answer: content,
                sourceMeetings: referenced
            )
        } catch {
            self.error = "Query failed: \(error.localizedDescription)"
        }

        isQuerying = false
    }

    /// Query a single meeting (for per-meeting chat, Task 4.2)
    func querySingleMeeting(_ text: String, meeting: Meeting, settings: AppSettings) async {
        isQuerying = true
        error = nil
        lastResponse = nil

        do {
            var context = "## \(meeting.title) (\(meeting.date.formatted(date: .abbreviated, time: .shortened)))\n"
            let summary = MeetingContextRetrievalService.effectiveSummary(for: meeting)
            if !summary.isEmpty {
                context += "Summary: \(summary)\n"
            }
            let transcript = MeetingContextRetrievalService.effectiveTranscript(for: meeting)
            if !transcript.isEmpty {
                context += "Transcript: \(transcript)\n"
            }
            let items = meeting.actionItems.map { item in
                "- \(item.title)" + (item.assignee.map { " (assigned: \($0))" } ?? "")
            }
            if !items.isEmpty {
                context += "Action Items:\n\(items.joined(separator: "\n"))\n"
            }

            let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
            let model = effectiveModel(for: .query, settings: settings, taskType: .chat)
            let content = try await client.chat(
                messages: [
                    .init(role: "system", content: """
                        You are a meeting assistant. Answer questions about this specific meeting \
                        based on the following data. Be specific and detailed.

                        \(context)
                        """),
                    .init(role: "user", content: text),
                ],
                model: model,
                format: nil
            )
            lastResponse = QueryResponse(
                answer: content,
                sourceMeetings: [meeting]
            )
        } catch {
            self.error = "Query failed: \(error.localizedDescription)"
        }

        isQuerying = false
    }

    /// Ask a question about a single meeting and return the answer directly (no shared state mutation).
    /// Used by per-meeting chat to maintain its own conversation history.
    func askAboutMeeting(_ text: String, chatHistory: [LLMChatMessage] = [], meeting: Meeting, settings: AppSettings, modelOverride: String? = nil) async throws -> String {
        var context = "## \(meeting.title) (\(meeting.date.formatted(date: .abbreviated, time: .shortened)))\n"
        let summary = MeetingContextRetrievalService.effectiveSummary(for: meeting)
        if !summary.isEmpty {
            context += "Summary: \(summary)\n"
        }
        let transcript = MeetingContextRetrievalService.effectiveTranscript(for: meeting)
        if !transcript.isEmpty {
            context += "Transcript: \(transcript)\n"
        }
        let items = meeting.actionItems.map { item in
            "- \(item.title)" + (item.assignee.map { " (assigned: \($0))" } ?? "")
        }
        if !items.isEmpty {
            context += "Action Items:\n\(items.joined(separator: "\n"))\n"
        }

        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
        let model = modelOverride.flatMap({ $0.isEmpty ? nil : $0 }) ?? effectiveModel(for: .query, settings: settings, taskType: .chat)

        var messages: [LLMChatMessage] = [
            .init(role: "system", content: """
                You are a meeting assistant. Answer questions about this specific meeting \
                based on the following data. Be specific and detailed.

                \(context)
                """),
        ]
        messages.append(contentsOf: chatHistory)
        messages.append(.init(role: "user", content: text))

        return try await client.chat(
            messages: messages,
            model: model,
            format: nil
        )
    }

    // MARK: - Private

    /// Build context string from meetings for the LLM
    private func buildContext(from meetings: [Meeting], limit: Int = 20) -> String {
        let recent = meetings.prefix(limit)
        return recent.map { meeting in
            var entry = "## \(meeting.title) (\(meeting.date.formatted(date: .abbreviated, time: .shortened)))\n"
            if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
                entry += "Attendees: \(attendees.joined(separator: ", "))\n"
            }
            let summary = MeetingContextRetrievalService.effectiveSummary(for: meeting)
            if !summary.isEmpty {
                entry += "Summary: \(summary)\n"
            }
            let items = meeting.actionItems.map { item in
                "- \(item.title)" + (item.assignee.map { " (assigned: \($0))" } ?? "")
            }
            if !items.isEmpty {
                entry += "Action Items:\n\(items.joined(separator: "\n"))\n"
            }
            return entry
        }.joined(separator: "\n---\n")
    }
}
