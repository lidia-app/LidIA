import Foundation
import SwiftData

@MainActor
@Observable
final class MeetingPipeline {
    private let llmClient: any LLMClient
    private let modelContext: ModelContext

    var processingStatus: String = ""

    init(llmClient: any LLMClient, modelContext: ModelContext) {
        self.llmClient = llmClient
        self.modelContext = modelContext
    }

    nonisolated static func buildRawText(from words: [TranscriptWord]) -> String {
        words.map(\.word).joined(separator: " ")
    }

    func process(
        meeting: Meeting,
        model: String,
        template: MeetingTemplate? = nil,
        vocabulary: [AppSettings.VocabularyEntry] = [],
        preserveUserEdits: Bool = true
    ) async throws {
        let rawText = Self.buildRawText(from: meeting.rawTranscript)
        guard !rawText.isEmpty else { return }

        guard !model.isEmpty else {
            meeting.processingError = "No model selected. Open Settings and choose a model, or click Fetch Models."
            meeting.status = .failed
            try modelContext.save()
            return
        }

        meeting.status = .processing
        meeting.processingError = nil
        meeting.templateID = template?.id
        try modelContext.save()

        // Step 1: Refine transcript
        processingStatus = "Refining transcript..."
        do {
            let refined = try await llmClient.refineTranscript(
                rawText: rawText,
                model: model,
                attendees: meeting.calendarAttendees,
                vocabulary: vocabulary
            )
            if preserveUserEdits,
               let edited = meeting.userEditedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
               !edited.isEmpty {
                meeting.refinedTranscript = edited
            } else {
                meeting.refinedTranscript = refined
                if !preserveUserEdits {
                    meeting.userEditedTranscript = nil
                }
            }
            try modelContext.save()
        } catch {
            meeting.processingError = "Transcript refinement failed: \(error.localizedDescription)"
            meeting.status = .failed
            try modelContext.save()
            processingStatus = "Failed"
            throw error
        }

        // Step 2: Summarize and extract action items.
        // Network retry is handled at client request level via RetryPolicy.
        processingStatus = "Generating summary..."
        do {
            let summary = try await llmClient.summarizeMeeting(
                transcript: effectiveTranscript(for: meeting, preserveUserEdits: preserveUserEdits),
                model: model,
                template: template,
                attendees: meeting.calendarAttendees
            )

            if meeting.title.isEmpty {
                meeting.title = summary.title
            }
            if preserveUserEdits,
               let editedSummary = meeting.userEditedSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !editedSummary.isEmpty {
                meeting.summary = editedSummary
            } else {
                meeting.summary = summary.flatSummary
                if !preserveUserEdits {
                    meeting.userEditedSummary = nil
                }
            }
            // Store structured summary if available
            if let structured = summary.toStructured() {
                meeting.structuredSummary = try? JSONEncoder().encode(structured)
            }

            for item in summary.actionItems {
                let actionItem = ActionItem(
                    title: item.title,
                    assignee: item.assignee,
                    deadline: item.deadline
                )
                actionItem.sourceQuote = item.sourceQuote
                meeting.actionItems.append(actionItem)
            }

            // Step 2b: Process user notes — extract action items and merge insights
            if !meeting.notes.isEmpty {
                processingStatus = "Processing notes..."
                await processNotes(meeting: meeting, model: model)
            }

            // Step 3: Detect suggested destinations for action items
            if !meeting.actionItems.isEmpty {
                processingStatus = "Detecting action destinations..."
                await detectDestinations(items: meeting.actionItems, model: model)
            }

            meeting.status = .complete
            try modelContext.save()
            processingStatus = "Done"
        } catch {
            meeting.processingError = "Summary generation failed: \(error.localizedDescription)"
            meeting.status = .failed
            try modelContext.save()
            processingStatus = "Failed"
            throw error
        }
    }

    private func detectDestinations(items: [ActionItem], model: String) async {
        let itemList = items.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
        let prompt = """
        For each action item below, suggest a destination:
        - "clickup" for tasks, tickets, bugs, feature requests
        - "notion" for documentation, notes, meeting records
        - "reminder" for personal follow-ups, reminders
        - "n8n" for complex workflows requiring automation
        - "none" if no specific destination fits

        Respond with ONLY a JSON array of strings, one per item, in order.
        Example: ["clickup", "reminder", "none"]

        Action items:
        \(itemList)
        """

        do {
            let response = try await llmClient.chat(
                messages: [LLMChatMessage(role: "user", content: prompt)],
                model: model,
                format: .json
            )
            // Strip markdown code fences if present
            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = cleaned.data(using: .utf8),
               let destinations = try? JSONDecoder().decode([String].self, from: data) {
                let validDestinations: Set<String> = ["clickup", "notion", "reminder", "n8n", "none"]
                for (index, item) in items.enumerated() where index < destinations.count {
                    let dest = destinations[index].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if validDestinations.contains(dest) {
                        item.suggestedDestination = dest
                    }
                }
            }
        } catch {
            // Non-fatal: items just won't have suggestions
        }
    }

    private func effectiveTranscript(for meeting: Meeting, preserveUserEdits: Bool) -> String {
        guard preserveUserEdits else { return meeting.refinedTranscript }
        let edited = meeting.userEditedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return edited.isEmpty ? meeting.refinedTranscript : edited
    }

    // MARK: - Notes Processing

    private func processNotes(meeting: Meeting, model: String) async {
        do {
            let response = try await llmClient.chat(
                messages: [
                    .init(role: "system", content: """
                        You are analyzing meeting notes written by the user during a meeting. \
                        Extract any action items, TODOs, follow-ups, or commitments mentioned in the notes. \
                        Also identify any insights or observations that aren't captured in the meeting summary.

                        Respond with ONLY a JSON object:
                        {"action_items": [{"title": "...", "assignee": null, "deadline": null}], "insights": ["insight 1"]}

                        Rules:
                        - Only extract clear action items (not vague observations)
                        - assignee and deadline can be null if not specified
                        - insights should be things the user noted that add context beyond the transcript
                        - Return empty arrays if nothing found
                        """),
                    .init(role: "user", content: """
                        Meeting: \(meeting.title)
                        Summary (first 500 chars): \(String(meeting.summary.prefix(500)))

                        User's notes:
                        \(meeting.notes)
                        """),
                ],
                model: model,
                format: .json
            )

            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = cleaned.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(NotesExtractionResult.self, from: data) else { return }

            for item in parsed.action_items {
                let isDuplicate = meeting.actionItems.contains { existing in
                    existing.title.localizedCaseInsensitiveContains(String(item.title.prefix(20)))
                }
                if !isDuplicate {
                    let actionItem = ActionItem(title: item.title, assignee: item.assignee)
                    actionItem.sourceQuote = "From notes"
                    meeting.actionItems.append(actionItem)
                }
            }

            if !parsed.insights.isEmpty {
                let insightsBlock = "\n\n## Notes & Observations\n\n" + parsed.insights.map { "- \($0)" }.joined(separator: "\n")
                meeting.summary += insightsBlock
            }
        } catch {
            // Non-fatal — notes processing failure shouldn't block the pipeline
        }
    }
}

private struct NotesExtractionResult: Decodable {
    struct NoteActionItem: Decodable {
        let title: String
        let assignee: String?
        let deadline: String?
    }
    let action_items: [NoteActionItem]
    let insights: [String]
}
