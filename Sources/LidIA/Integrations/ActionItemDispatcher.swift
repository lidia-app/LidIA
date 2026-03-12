import Foundation
import SwiftData

enum DispatchError: LocalizedError {
    case notConfigured(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured(let name): "\(name) is not configured. Check Settings → Integrations."
        }
    }
}

@MainActor
enum ActionItemDispatcher {
    static func dispatch(
        item: ActionItem,
        meetingTitle: String,
        destination: String,
        settings: AppSettings,
        eventKitManager: EventKitManager,
        modelContext: ModelContext
    ) async throws {
        switch destination {
        case "notion":
            _ = try await ActionItemNotionSyncService.sync(
                targets: [ActionItemNotionSyncService.SyncTarget(item: item, meetingTitle: meetingTitle)],
                settings: settings,
                modelContext: modelContext
            )

        case "reminder":
            let reminderID = await eventKitManager.syncReminder(
                reminderID: item.reminderID,
                title: item.title,
                deadlineText: item.displayDeadline,
                deadlineDate: item.deadlineDate,
                isCompleted: item.isCompleted
            )
            item.reminderID = reminderID

        case "n8n":
            guard settings.n8nEnabled, !settings.n8nWebhookURL.isEmpty else {
                throw DispatchError.notConfigured("n8n")
            }
            let payload = N8nClient.WebhookPayload(
                meetingTitle: meetingTitle,
                date: ISO8601DateFormatter().string(from: .now),
                duration: 0,
                summary: "",
                actionItems: [N8nClient.ActionItemPayload(
                    title: item.title,
                    assignee: item.assignee,
                    deadline: item.displayDeadline
                )],
                attendees: [],
                transcript: ""
            )
            await N8nClient.sendWebhook(
                payload: payload,
                webhookURL: settings.n8nWebhookURL,
                authHeader: settings.n8nAuthHeader
            )

        case "clickup":
            guard !settings.clickUpAPIKey.isEmpty, !settings.clickUpListID.isEmpty else {
                throw DispatchError.notConfigured("ClickUp")
            }
            try await ClickUpClient.createTask(
                title: item.title,
                description: "From meeting: \(meetingTitle)\nAssignee: \(item.assignee ?? "Unassigned")\nDeadline: \(item.displayDeadline ?? "None")",
                listID: settings.clickUpListID,
                apiKey: settings.clickUpAPIKey
            )

        default:
            break
        }
    }
}
