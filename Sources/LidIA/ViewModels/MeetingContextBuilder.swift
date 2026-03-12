import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "io.lidia.app", category: "MeetingContextBuilder")

/// Builds LLM context from meetings and action items based on the selected scope.
@MainActor
@Observable
final class MeetingContextBuilder {

    // MARK: - Types

    struct ContextBundle: Sendable {
        let contextText: String
        let candidateSourceTitles: [String]
        let hasEvidence: Bool
    }

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private var selectedMeeting: Meeting?

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func updateSelectedMeeting(_ meeting: Meeting?) {
        selectedMeeting = meeting
    }

    // MARK: - Context Building

    func buildContextBundle(for query: String, scope: ChatBarViewModel.ContextScope) -> ContextBundle {
        switch scope {
        case .selectedMeeting:
            if let selectedMeeting {
                let meetings = [selectedMeeting]
                return ContextBundle(
                    contextText: context(for: meetings, title: "Selected meeting context"),
                    candidateSourceTitles: meetingTitles(for: meetings),
                    hasEvidence: true
                )
            }
            return ContextBundle(
                contextText: "No selected meeting. Ask from All meetings scope instead.",
                candidateSourceTitles: [],
                hasEvidence: false
            )

        case .allMeetings:
            guard let meetings = try? fetchMeetings(limit: 60, includeInProgress: false), !meetings.isEmpty else {
                return ContextBundle(
                    contextText: "No meeting data available yet.",
                    candidateSourceTitles: [],
                    hasEvidence: false
                )
            }
            let selected = MeetingContextRetrievalService.relevantMeetings(for: query, from: meetings, limit: 12)
            guard !selected.isEmpty else {
                return ContextBundle(
                    contextText: "No relevant meeting data available for this query.",
                    candidateSourceTitles: [],
                    hasEvidence: false
                )
            }
            return ContextBundle(
                contextText: context(for: selected, title: "Meeting context"),
                candidateSourceTitles: meetingTitles(for: selected),
                hasEvidence: true
            )

        case .myNotes:
            guard let noteMeetings = try? fetchMeetingsWithNotes(limit: 30), !noteMeetings.isEmpty else {
                return ContextBundle(
                    contextText: "No notes available yet.",
                    candidateSourceTitles: [],
                    hasEvidence: false
                )
            }
            let selected = MeetingContextRetrievalService.relevantMeetings(for: query, from: noteMeetings, limit: 12)
            return ContextBundle(
                contextText: context(for: selected, title: "Notes context"),
                candidateSourceTitles: meetingTitles(for: selected),
                hasEvidence: !selected.isEmpty
            )
        }
    }

    // MARK: - Grounding / Source Analysis

    func deriveSourceTitles(answer: String, candidateTitles: [String]) -> [String] {
        let normalized = answer.lowercased()
        let explicit = candidateTitles.filter { title in
            normalized.contains(title.lowercased())
        }

        if !explicit.isEmpty {
            return Array(explicit.prefix(4))
        }
        return Array(candidateTitles.prefix(3))
    }

    func deriveGroundingConfidence(answer: String, sourceCount: Int) -> ChatBarMessage.GroundingConfidence {
        let normalized = answer.lowercased()
        if normalized.contains("[error:") || indicatesInsufficientEvidence(in: normalized) {
            return .low
        }
        if sourceCount >= 2 {
            return .high
        }
        if sourceCount == 1 {
            return .medium
        }
        return .low
    }

    /// Fetches meetings for suggestion logic (checks if any meetings exist).
    func fetchMeetings(limit: Int, includeInProgress: Bool) throws -> [Meeting] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)

        if includeInProgress {
            return Array(all.prefix(limit))
        }

        let completed = all.filter { $0.status == .complete }
        return Array(completed.prefix(limit))
    }

    // MARK: - Private Helpers

    private func meetingTitles(for meetings: [Meeting]) -> [String] {
        meetings
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func indicatesInsufficientEvidence(in text: String) -> Bool {
        text.contains("insufficient evidence")
            || text.contains("not enough information")
            || text.contains("don't have enough")
            || text.contains("cannot determine")
    }

    private func context(for meetings: [Meeting], title: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var parts: [String] = [title + ":"]

        for meeting in meetings {
            var entry = "## \(meeting.title.isEmpty ? "Untitled" : meeting.title)"
            entry += "\nDate: \(formatter.string(from: meeting.date))"

            if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
                entry += "\nAttendees: \(attendees.joined(separator: ", "))"
            }

            if !meeting.summary.isEmpty {
                entry += "\nSummary: \(meeting.summary)"
            }

            if !meeting.notes.isEmpty {
                entry += "\nNotes: \(String(meeting.notes.prefix(800)))"
            }

            if !meeting.actionItems.isEmpty {
                let items = meeting.actionItems.map { item in
                    "- [\(item.isCompleted ? "x" : " ")] \(item.title)"
                        + (item.assignee.map { " (@\($0))" } ?? "")
                }.joined(separator: "\n")
                entry += "\nAction Items:\n\(items)"
            }

            parts.append(entry)
        }

        return parts.joined(separator: "\n\n")
    }

    private func fetchMeetingsWithNotes(limit: Int) throws -> [Meeting] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        let notes = all.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(notes.prefix(limit))
    }
}
