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
        eventKitManager: EventKitManager?
    ) async {
        // Snapshot values needed by concurrent tasks before leaving MainActor
        let shouldSendNotion = settings.notionAutoSend && !settings.notionAPIKey.isEmpty && !settings.notionDatabaseID.isEmpty
        let notionAPIKey = settings.notionAPIKey
        let notionDatabaseID = settings.notionDatabaseID
        let meetingTitle = meeting.title
        let meetingDate = meeting.date
        let meetingDuration = meeting.duration
        let meetingSummary = meeting.summary
        let actionItemSnapshot = meeting.actionItems.map { (title: $0.title, assignee: $0.assignee, deadline: $0.displayDeadline) }
        let shouldSendReminders = eventKitManager != nil && settings.remindersAutoSend && settings.remindersEnabled
        let shouldSendN8n = settings.n8nEnabled && settings.n8nAutoSend && !settings.n8nWebhookURL.isEmpty
        let calendarAttendees = meeting.calendarAttendees ?? []
        let meetingTranscript = MeetingContextRetrievalService.effectiveTranscript(for: meeting)
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

        // n8n webhook (fire-and-forget via actor)
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
                        deadline: $0.deadline
                    )
                } : [],
                attendees: n8nSendAttendees ? calendarAttendees : [],
                transcript: n8nSendTranscript ? meetingTranscript : ""
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

        // Send completion notification
        sendCompletionNotification(meeting: meeting)
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
}
