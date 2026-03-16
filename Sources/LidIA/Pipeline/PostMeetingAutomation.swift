import Foundation
import os
import SwiftData
import UserNotifications

@MainActor
struct PostMeetingAutomation {
    nonisolated private static let logger = Logger(subsystem: "io.lidia.app", category: "PostMeetingAutomation")
    static func run(
        meeting: Meeting,
        modelContext: ModelContext,
        settings: AppSettings,
        eventKitManager: EventKitManager?,
        modelManager: ModelManager? = nil
    ) async {
        // Snapshot values needed by concurrent tasks before leaving MainActor
        let shouldSendNotion = settings.notionAutoSend && !settings.notionAPIKey.isEmpty && !settings.notionDatabaseID.isEmpty
        let notionAPIKey = settings.notionAPIKey
        let notionDatabaseID = settings.notionDatabaseID
        let meetingTitle = meeting.title
        let meetingDate = meeting.date
        let meetingDuration = meeting.duration
        let meetingSummary = meeting.summary
        let actionItemSnapshot = meeting.actionItems.map { (title: $0.title, assignee: $0.assignee, deadline: $0.displayDeadline, priority: $0.priority, suggestedDestination: $0.suggestedDestination) }
        let shouldSendReminders = eventKitManager != nil && settings.remindersAutoSend && settings.remindersEnabled
        let shouldSendN8n = settings.n8nEnabled && settings.n8nAutoSend && !settings.n8nWebhookURL.isEmpty
        let calendarAttendees = meeting.calendarAttendees ?? []
        let meetingTranscript = MeetingContextRetrievalService.effectiveTranscript(for: meeting)
        let meetingNotes = meeting.notes
        let meetingTemplateName: String? = meeting.templateID.flatMap { tid in settings.meetingTemplates.first { $0.id == tid }?.name }
        let n8nWebhookURL = settings.n8nWebhookURL
        let n8nAuthHeader = settings.n8nAuthHeader.isEmpty ? nil : settings.n8nAuthHeader
        let notionSendSummary = settings.notionSendSummary
        let notionSendActionItems = settings.notionSendActionItems
        let n8nSendSummary = settings.n8nSendSummary
        let n8nSendActionItems = settings.n8nSendActionItems
        let n8nSendAttendees = settings.n8nSendAttendees
        let n8nSendTranscript = settings.n8nSendTranscript
        let remindersMyItemsOnly = settings.remindersMyItemsOnly
        let displayName = settings.displayName
        let shouldSendSlack = settings.slackEnabled && settings.slackAutoSend && !settings.slackBotToken.isEmpty && !settings.slackChannel.isEmpty
        let slackBotToken = settings.slackBotToken
        let slackChannel = settings.slackChannel
        let slackSendSummary = settings.slackSendSummary
        let slackSendActionItems = settings.slackSendActionItems
        let slackSendAttendees = settings.slackSendAttendees

        // --- Run independent integrations concurrently ---

        // Notion (network call via actor, returns page ID)
        async let notionResult: String? = {
            guard shouldSendNotion else { return nil }
            do {
                let notion = NotionClient(apiKey: notionAPIKey)
                var bodyParts: [String] = []
                if notionSendSummary {
                    bodyParts.append("""
                    ## Summary
                    \(meetingSummary)
                    """)
                }
                if notionSendActionItems {
                    bodyParts.append("""
                    ## Action Items
                    \(actionItemSnapshot.map {
                        var line = "- \($0.title)"
                        if let deadline = $0.deadline {
                            line += " (due: \(deadline))"
                        }
                        return line
                    }.joined(separator: "\n"))
                    """)
                }
                let body = bodyParts.joined(separator: "\n\n")
                return try await notion.createMeetingPage(
                    databaseID: notionDatabaseID,
                    title: meetingTitle,
                    date: meetingDate,
                    duration: meetingDuration,
                    bodyMarkdown: body
                )
            } catch {
                logger.error("Notion sync failed: \(error)")
                return nil
            }
        }()

        // Build attendee context on MainActor before entering async closure
        let attendeeContexts: [N8nClient.AttendeeContext] = {
            guard shouldSendN8n, n8nSendAttendees else { return [] }
            let descriptor = FetchDescriptor<Meeting>()
            let allMeetings = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .complete }
            return calendarAttendees.map { attendee in
                let pastMeetings = allMeetings.filter { m in
                    m.calendarAttendees?.contains(where: { $0.localizedCaseInsensitiveCompare(attendee) == .orderedSame }) == true
                }
                let allItems = pastMeetings.flatMap(\.actionItems)
                let openItems = allItems.filter { !$0.isCompleted }
                let overdueItems = openItems.filter { $0.deadlineDate != nil && $0.deadlineDate! < Date() }
                return N8nClient.AttendeeContext(
                    email: attendee,
                    openActionItems: openItems.count,
                    overdueActionItems: overdueItems.count,
                    lastMeetingDate: pastMeetings.sorted(by: { $0.date > $1.date }).first.map { ISO8601DateFormatter().string(from: $0.date) },
                    totalMeetings: pastMeetings.count
                )
            }
        }()

        // n8n webhook (fire-and-forget via actor) — enriched payload with attendee context
        async let n8nDone: Void = {
            guard shouldSendN8n else { return }
            let payload = N8nClient.WebhookPayload(
                meetingTitle: meetingTitle,
                date: ISO8601DateFormatter().string(from: meetingDate),
                duration: meetingDuration,
                summary: n8nSendSummary ? meetingSummary : "",
                actionItems: n8nSendActionItems ? actionItemSnapshot.map {
                    N8nClient.ActionItemPayload(
                        title: $0.title,
                        assignee: $0.assignee,
                        deadline: $0.deadline,
                        priority: $0.priority,
                        suggestedDestination: $0.suggestedDestination
                    )
                } : [],
                attendees: n8nSendAttendees ? calendarAttendees : [],
                transcript: n8nSendTranscript ? meetingTranscript : "",
                notes: meetingNotes,
                meetingType: meetingTemplateName,
                attendeeContext: attendeeContexts
            )
            await N8nClient.sendWebhook(
                payload: payload,
                webhookURL: n8nWebhookURL,
                authHeader: n8nAuthHeader
            )
        }()

        // Slack (fire-and-forget via actor)
        async let slackDone: Void = {
            guard shouldSendSlack else { return }
            let message = SlackClient.SlackMessage(
                channel: slackChannel,
                meetingTitle: meetingTitle,
                date: meetingDate,
                duration: meetingDuration,
                summary: slackSendSummary ? meetingSummary : nil,
                actionItems: slackSendActionItems ? actionItemSnapshot.map {
                    (title: $0.title, assignee: $0.assignee, deadline: $0.deadline)
                } : [],
                attendees: slackSendAttendees ? calendarAttendees : nil
            )
            await SlackClient.postMeetingSummary(message: message, botToken: slackBotToken)
        }()

        // Await concurrent network integrations
        let pageID = await notionResult
        await n8nDone
        await slackDone

        // Apple Reminders — runs on MainActor (mutates SwiftData model)
        if shouldSendReminders, let ekManager = eventKitManager {
            let itemsToCreate = remindersMyItemsOnly
                ? meeting.actionItems.filter { item in
                    let assignee = item.assignee?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return assignee.isEmpty || assignee.localizedCaseInsensitiveCompare(displayName) == .orderedSame
                }
                : meeting.actionItems
            for actionItem in itemsToCreate {
                if let reminderID = await ekManager.createReminder(
                    title: actionItem.title,
                    deadline: actionItem.displayDeadline
                ) {
                    actionItem.reminderID = reminderID
                }
            }
        }

        // Apply results back to model (MainActor)
        if let pageID {
            meeting.notionPageID = pageID
        }
        if shouldSendNotion || shouldSendReminders {
            try? modelContext.save()
        }

        // Mark talking points as used
        if let attendees = meeting.calendarAttendees {
            let descriptor = FetchDescriptor<TalkingPoint>()
            if let talkingPoints = try? modelContext.fetch(descriptor) {
                for tp in talkingPoints where !tp.isUsed {
                    if attendees.contains(where: { $0.lowercased() == tp.personIdentifier.lowercased() }) {
                        tp.isUsed = true
                    }
                }
                try? modelContext.save()
            }
        }

        // Index in Spotlight
        SpotlightIndexer.indexMeeting(meeting)

        // Markdown vault export
        if settings.vaultExportEnabled {
            do {
                try VaultExporter.export(meeting: meeting, settings: settings)
            } catch {
                logger.error("Vault export failed: \(error.localizedDescription)")
            }
        }

        // Autopilot: auto-dispatch action items with confirmed or suggested destinations
        if settings.autopilotEnabled {
            var autopilotChanged = false
            for item in meeting.actionItems {
                if let destination = item.confirmedDestination ?? item.suggestedDestination {
                    // Mark suggested destinations as confirmed so they are not sent again
                    if item.confirmedDestination == nil {
                        item.confirmedDestination = destination
                        autopilotChanged = true
                    }
                }
            }
            if autopilotChanged {
                try? modelContext.save()
            }
        }

        // Send completion notification
        sendCompletionNotification(meeting: meeting)

        // Proactive post-meeting nudges
        if !meeting.actionItems.isEmpty {
            await generatePostMeetingNudges(
                meeting: meeting,
                settings: settings,
                modelManager: modelManager
            )
        }
    }

    private static func sendCompletionNotification(meeting: Meeting) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting Processed"
        let actionCount = meeting.actionItems.count
        content.body = "\(meeting.title) — \(actionCount) action item\(actionCount == 1 ? "" : "s") created"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lidia.processed.\(meeting.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Proactive Post-Meeting Nudges

    @MainActor
    private static func generatePostMeetingNudges(
        meeting: Meeting,
        settings: AppSettings,
        modelManager: ModelManager?
    ) async {
        let displayName = settings.displayName.lowercased()

        // Find items assigned to the user or unassigned
        let myItems = meeting.actionItems.filter { item in
            let assignee = (item.assignee ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return assignee.isEmpty || assignee.contains(displayName) || displayName.contains(assignee)
        }

        guard !myItems.isEmpty else { return }

        // Categorize action items
        let followUpKeywords = ["ping", "follow up", "email", "message", "share", "send", "notify", "tell", "reach out", "contact", "slack"]
        var followUps: [ActionItem] = []
        var tickets: [ActionItem] = []
        var reminders: [ActionItem] = []

        for item in myItems {
            let titleLower = item.title.lowercased()
            if followUpKeywords.contains(where: { titleLower.contains($0) }) {
                followUps.append(item)
            } else if item.suggestedDestination == "clickup" || item.suggestedDestination == "notion" {
                tickets.append(item)
            } else {
                reminders.append(item)
            }
        }

        var nudgeCount = 0
        let maxNudges = 3

        // Follow-up nudges with LLM-drafted messages
        for item in followUps.prefix(2) where nudgeCount < maxNudges {
            var draft = ""
            do {
                let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
                let model = effectiveModel(for: .query, settings: settings, taskType: .chat)
                draft = try await client.chat(
                    messages: [
                        .init(role: "system", content: "Write a very short (1-2 sentence) professional message for this follow-up. No greeting, no sign-off, just the content. Be direct."),
                        .init(role: "user", content: "Action item: \(item.title)\nMeeting context: \(meeting.title)"),
                    ],
                    model: model,
                    format: nil
                )
            } catch {
                logger.warning("Failed to draft nudge message: \(error.localizedDescription)")
                draft = ""
            }

            let body = draft.isEmpty
                ? "You agreed to: \(item.title)"
                : "You agreed to: \(item.title)\n\nDraft: \"\(draft.trimmingCharacters(in: .whitespacesAndNewlines))\""

            sendNudgeNotification(
                title: "Follow-up from \(meeting.title)",
                body: body,
                identifier: "lidia.nudge.\(item.id)"
            )
            nudgeCount += 1
        }

        // Ticket nudges
        for item in tickets.prefix(1) where nudgeCount < maxNudges {
            let dest = item.suggestedDestination ?? "your task tracker"
            sendNudgeNotification(
                title: "Create ticket?",
                body: "From \(meeting.title): \"\(item.title)\" — should this be a \(dest) ticket?",
                identifier: "lidia.nudge.\(item.id)"
            )
            nudgeCount += 1
        }

        // Remaining reminder nudges (fill up to maxNudges)
        for item in reminders where nudgeCount < maxNudges {
            sendNudgeNotification(
                title: "Action item from \(meeting.title)",
                body: item.title,
                identifier: "lidia.nudge.\(item.id)"
            )
            nudgeCount += 1
        }

        if nudgeCount > 0 {
            logger.info("Scheduled \(nudgeCount) post-meeting nudge(s) for \(meeting.title)")
        }
    }

    private static func sendNudgeNotification(title: String, body: String, identifier: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Delay nudges by 2 minutes so they don't overlap with the "Meeting Processed" notification
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
