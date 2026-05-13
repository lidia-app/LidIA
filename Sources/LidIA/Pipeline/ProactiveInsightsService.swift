import Foundation
import os
import SwiftData

/// Generates proactive pre-meeting briefs as InboxNotifications shortly before
/// upcoming calendar events. Surfaces in the FOR YOU dispatcher card section.
///
/// Today: pre-meeting briefs (this file).
/// Roadmap: stale action-item nudges, re-engagement reminders, decision tracker.
@MainActor
@Observable
final class ProactiveInsightsService {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "ProactiveInsights")
    private var scheduler: Task<Void, Never>?

    /// How many minutes before the event start we generate the brief.
    /// Slightly larger than the system notification window so the dispatcher
    /// card is ready when the system "5 min before" reminder fires.
    private let prepWindowMinutes: Int = 15

    /// Minimum gap between scheduler polls (seconds). Cheap — only reads in-memory
    /// upcomingEvents and a SwiftData query.
    private let pollInterval: TimeInterval = 60

    /// Cap of briefs to generate per tick to avoid token spam if many events stack.
    private let maxBriefsPerTick: Int = 2

    func startScheduler(
        settings: AppSettings,
        modelContext: ModelContext,
        modelManager: ModelManager?,
        googleCalendarMonitor: GoogleCalendarMonitor,
        eventKitManager: EventKitManager
    ) {
        scheduler?.cancel()
        scheduler = Task { [weak self] in
            // Initial tick on startup so freshly-relaunched app catches imminent events.
            await self?.tick(
                settings: settings,
                modelContext: modelContext,
                modelManager: modelManager,
                googleCalendarMonitor: googleCalendarMonitor,
                eventKitManager: eventKitManager
            )
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 60))
                guard !Task.isCancelled else { return }
                await self?.tick(
                    settings: settings,
                    modelContext: modelContext,
                    modelManager: modelManager,
                    googleCalendarMonitor: googleCalendarMonitor,
                    eventKitManager: eventKitManager
                )
            }
        }
    }

    func stopScheduler() {
        scheduler?.cancel()
        scheduler = nil
    }

    // MARK: - Tick

    private func tick(
        settings: AppSettings,
        modelContext: ModelContext,
        modelManager: ModelManager?,
        googleCalendarMonitor: GoogleCalendarMonitor,
        eventKitManager: EventKitManager
    ) async {
        // Reuse the existing prep-notifications-enabled flag.
        guard settings.prepNotificationsEnabled else { return }

        let now = Date.now
        let horizonEnd = now.addingTimeInterval(TimeInterval(prepWindowMinutes * 60))
        var candidates: [PrepCandidate] = []

        for ge in googleCalendarMonitor.upcomingEvents {
            guard ge.start > now, ge.start <= horizonEnd else { continue }
            guard !ge.attendees.isEmpty else { continue }
            candidates.append(PrepCandidate(
                eventID: "google:\(ge.id)",
                title: ge.title,
                start: ge.start,
                attendees: ge.attendees
            ))
        }

        for ae in eventKitManager.upcomingEvents {
            guard ae.start > now, ae.start <= horizonEnd else { continue }
            guard !ae.attendees.isEmpty else { continue }
            candidates.append(PrepCandidate(
                eventID: "apple:\(ae.id)",
                title: ae.title,
                start: ae.start,
                attendees: ae.attendees
            ))
        }

        guard !candidates.isEmpty else { return }

        // Filter out events we've already briefed.
        let existingBriefedIDs = existingPrepEventIDs(modelContext: modelContext)
        let fresh = candidates.filter { !existingBriefedIDs.contains($0.eventID) }
        guard !fresh.isEmpty else { return }

        // Generate at most N briefs per tick, soonest-starting first.
        let toBrief = fresh.sorted { $0.start < $1.start }.prefix(maxBriefsPerTick)
        for candidate in toBrief {
            await generateBrief(
                candidate: candidate,
                settings: settings,
                modelManager: modelManager,
                modelContext: modelContext
            )
        }
    }

    // MARK: - Brief generation

    private func generateBrief(
        candidate: PrepCandidate,
        settings: AppSettings,
        modelManager: ModelManager?,
        modelContext: ModelContext
    ) async {
        let descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\Meeting.date, order: .reverse)])
        let allMeetings = (try? modelContext.fetch(descriptor)) ?? []
        let completed = allMeetings.filter { $0.status == .complete }
        let related = MeetingContextRetrievalService.meetingsForAttendees(
            candidate.attendees,
            in: completed,
            limit: 4
        )
        let openItems = related
            .flatMap(\.actionItems)
            .filter { !$0.isCompleted }

        // No prior context — skip rather than generate empty filler.
        if related.isEmpty && openItems.isEmpty {
            Self.logger.info("No prior context for event \(candidate.eventID, privacy: .public); skipping brief")
            return
        }

        let contextString = buildContextString(
            candidate: candidate,
            related: related,
            openItems: openItems
        )

        let prompt = """
        You are a meeting prep assistant. In 2–3 short sentences (no bullets, no preamble), \
        summarize what the user should know walking into this meeting. Reference the most \
        relevant prior context and call out open action items only if they're directly relevant. \
        Be specific. If there's nothing meaningful to surface, say so briefly.

        \(contextString)
        """

        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .summarization)
        let model = effectiveModel(for: .summary, settings: settings, taskType: .summarization)

        do {
            let brief = try await client.chat(
                messages: [LLMChatMessage(role: "user", content: prompt)],
                model: model,
                format: nil
            )
            let trimmed = brief.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let payload = InboxNotification.encodePayload(
                meetingTitle: candidate.title,
                eventID: candidate.eventID
            )
            let notif = InboxNotification(
                type: "meeting_prep",
                title: "Prep: \(candidate.title)",
                body: trimmed,
                actionPayload: payload
            )
            modelContext.insert(notif)
            try? modelContext.save()
            Self.logger.info("Generated prep brief for \(candidate.title, privacy: .public)")
        } catch {
            Self.logger.error("Brief generation failed for \(candidate.eventID, privacy: .public): \(error.localizedDescription)")
        }
    }

    private func buildContextString(
        candidate: PrepCandidate,
        related: [Meeting],
        openItems: [ActionItem]
    ) -> String {
        var lines: [String] = []
        lines.append("UPCOMING MEETING: \(candidate.title)")
        lines.append("STARTS: \(candidate.start.formatted(date: .abbreviated, time: .shortened))")
        let attendeesPreview = candidate.attendees.prefix(6).joined(separator: ", ")
        lines.append("ATTENDEES: \(attendeesPreview)")

        if let last = related.first {
            lines.append("")
            lines.append("LAST MEETING WITH THESE ATTENDEES: \(last.title) on \(last.date.formatted(date: .abbreviated, time: .omitted))")
            let summary = MeetingContextRetrievalService.effectiveSummary(for: last)
            if !summary.isEmpty {
                let snippet = String(summary.prefix(500))
                lines.append("SUMMARY: \(snippet)")
            }
        }

        if related.count > 1 {
            lines.append("")
            lines.append("OTHER RECENT MEETINGS WITH THESE ATTENDEES:")
            for meeting in related.dropFirst().prefix(3) {
                lines.append("- \(meeting.title) (\(meeting.date.formatted(date: .abbreviated, time: .omitted)))")
            }
        }

        if !openItems.isEmpty {
            lines.append("")
            lines.append("OPEN ACTION ITEMS FROM PRIOR MEETINGS:")
            for item in openItems.prefix(8) {
                var line = "- \(item.title)"
                if let assignee = item.assignee, !assignee.isEmpty {
                    line += " (assignee: \(assignee))"
                }
                if let deadline = item.displayDeadline {
                    line += " (due: \(deadline))"
                }
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Dedup

    private func existingPrepEventIDs(modelContext: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<InboxNotification>(
            predicate: #Predicate<InboxNotification> { $0.type == "meeting_prep" }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        return Set(existing.compactMap { $0.sourceEventID })
    }
}

private struct PrepCandidate {
    let eventID: String
    let title: String
    let start: Date
    let attendees: [String]
}
