import Foundation
import SwiftData
import os

/// Caches meeting context between voice turns to avoid re-fetching on every turn.
/// Invalidated when meetings change, topic drifts, or TTL expires.
@MainActor
final class VoiceMeetingContextCache {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "VoiceContextCache")

    /// Cached list of completed meetings, refreshed when count changes.
    private var cachedMeetings: [Meeting] = []
    private var cachedMeetingCount: Int = 0
    private var meetingsLastFetched: Date = .distantPast

    /// Cached formatted context strings keyed by normalized query tokens.
    private var contextCache: [Set<String>: CachedContext] = [:]

    /// How long cached context remains valid.
    private let contextTTL: TimeInterval = 30

    /// How long the meetings list remains valid before re-checking count.
    private let meetingsCheckInterval: TimeInterval = 10

    private let modelContext: ModelContext

    struct CachedContext {
        let formattedContext: String
        let selectedMeetingIDs: Set<PersistentIdentifier>
        let timestamp: Date
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Fetch meeting context for a query, using cache when possible.
    func meetingContext(for query: String) -> String {
        let meetings = refreshMeetingsIfNeeded()
        guard !meetings.isEmpty else { return "" }

        let tokens = queryTokens(from: query)
        let q = query.lowercased()

        // Check cache
        if let cached = contextCache[tokens],
           Date.now.timeIntervalSince(cached.timestamp) < contextTTL {
            Self.logger.debug("Context cache hit for tokens: \(tokens.joined(separator: ","))")
            return cached.formattedContext
        }

        // Cache miss — compute
        let expandedKeywords = ["last week", "this month", "all my", "every", "action items", "what did i promise", "next week"]
        let expandedSearch = expandedKeywords.contains(where: { q.contains($0) })
        let selected = MeetingContextRetrievalService.relevantMeetings(
            for: query, from: meetings, limit: expandedSearch ? 30 : 10
        )

        let formatted = formatMeetingContext(selected)
        let meetingIDs = Set(selected.map(\.persistentModelID))
        contextCache[tokens] = CachedContext(
            formattedContext: formatted,
            selectedMeetingIDs: meetingIDs,
            timestamp: .now
        )

        Self.logger.debug("Context cache miss — cached \(selected.count) meetings for \(tokens.count) tokens")
        return formatted
    }

    /// Speculative pre-fetch using partial transcript. Returns cached context if available.
    func speculativeContext(partialTranscript: String) -> String? {
        let tokens = queryTokens(from: partialTranscript)
        guard !tokens.isEmpty else { return nil }

        // Check if any cached entry has significant overlap with partial tokens
        for (cachedTokens, cached) in contextCache {
            guard Date.now.timeIntervalSince(cached.timestamp) < contextTTL else { continue }
            let overlap = tokens.intersection(cachedTokens)
            if overlap.count >= max(1, tokens.count / 2) {
                return cached.formattedContext
            }
        }
        return nil
    }

    /// Invalidate all cached context (call on session end, meeting change, etc).
    func invalidate() {
        cachedMeetings = []
        cachedMeetingCount = 0
        meetingsLastFetched = .distantPast
        contextCache = [:]
    }

    /// Invalidate only context cache but keep meetings list.
    func invalidateContextOnly() {
        contextCache = [:]
    }

    // MARK: - Private

    private func refreshMeetingsIfNeeded() -> [Meeting] {
        let now = Date.now
        guard now.timeIntervalSince(meetingsLastFetched) >= meetingsCheckInterval else {
            return cachedMeetings
        }

        let context = modelContext
        do {
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let allMeetings = try context.fetch(descriptor)
            let completed = allMeetings.filter { $0.status == .complete }

            if completed.count != cachedMeetingCount {
                // Meeting count changed — invalidate context cache too
                contextCache = [:]
                Self.logger.info("Meeting count changed (\(self.cachedMeetingCount) → \(completed.count)), invalidated context cache")
            }

            cachedMeetings = completed
            cachedMeetingCount = completed.count
            meetingsLastFetched = now
            return completed
        } catch {
            Self.logger.error("Failed to fetch meetings: \(error)")
            return cachedMeetings
        }
    }

    private func queryTokens(from text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 }
        )
    }

    private func formatMeetingContext(_ meetings: [Meeting]) -> String {
        var entries: [String] = []
        for meeting in meetings {
            var entry = "## \(meeting.title) (\(meeting.date.formatted(date: .abbreviated, time: .shortened)))\n"
            if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
                entry += "Attendees: \(attendees.joined(separator: ", "))\n"
            }
            let summary = MeetingContextRetrievalService.effectiveSummary(for: meeting)
            if !summary.isEmpty {
                entry += "Summary: \(summary)\n"
            }
            for item in meeting.actionItems {
                let check = item.isCompleted ? "x" : " "
                let assignee = item.assignee.map { " (assigned: \($0))" } ?? ""
                entry += "- [\(check)] \(item.title)\(assignee)\n"
            }
            entries.append(entry)
        }
        return entries.joined(separator: "\n---\n")
    }
}
