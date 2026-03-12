import Foundation
import UserNotifications

struct ProactiveNotificationPayload: Sendable {
    enum Destination: String, Sendable {
        case calendar
        case actionItems
    }

    let destination: Destination
    let eventID: String?
}

enum NotificationDispatcher {
    enum Category: String, CaseIterable, Sendable {
        case morningDigest = "morning-digest"
        case preMeetingPrep = "pre-meeting-prep"
        case postMeetingNudge = "post-meeting-nudge"
        case actionItemReminder = "action-item-reminder"
    }

    static let viewActionIdentifier = "VIEW_IN_LIDIA"
    static let destinationUserInfoKey = "proactiveDestination"
    static let eventIDUserInfoKey = "proactiveEventID"

    static var categoryIdentifiers: [String] {
        Category.allCases.map(\.rawValue)
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    static func notificationCategories() -> Set<UNNotificationCategory> {
        let viewAction = UNNotificationAction(
            identifier: viewActionIdentifier,
            title: "View in LidIA",
            options: [.foreground]
        )

        return Set(Category.allCases.map { category in
            UNNotificationCategory(
                identifier: category.rawValue,
                actions: [viewAction],
                intentIdentifiers: []
            )
        })
    }

    static func sendMorningDigest(eventCount: Int, actionItemCount: Int, details: String) {
        send(
            category: .morningDigest,
            title: "Morning Digest",
            body: "\(eventCount) event\(eventCount == 1 ? "" : "s") today, \(actionItemCount) action item\(actionItemCount == 1 ? "" : "s") due. \(details)",
            payload: ProactiveNotificationPayload(destination: .calendar, eventID: nil)
        )
    }

    static func sendPreMeetingPrep(eventTitle: String, minutesBefore: Int, summary: String, eventID: String?) {
        send(
            category: .preMeetingPrep,
            title: "Meeting Prep",
            body: "\(eventTitle) starts in \(minutesBefore) min. \(summary)",
            payload: ProactiveNotificationPayload(destination: .calendar, eventID: eventID)
        )
    }

    static func sendPostMeetingNudge(eventTitle: String, eventID: String?) {
        send(
            category: .postMeetingNudge,
            title: "Meeting Follow-Up",
            body: "\(eventTitle) ended recently. Add quick notes or retry processing in LidIA.",
            payload: ProactiveNotificationPayload(destination: .calendar, eventID: eventID)
        )
    }

    static func sendActionItemReminder(count: Int, titles: [String]) {
        let preview = titles.prefix(3).joined(separator: ", ")
        let suffix = preview.isEmpty ? "" : " \(preview)"
        send(
            category: .actionItemReminder,
            title: "Action Item Reminder",
            body: "\(count) action item\(count == 1 ? "" : "s") due today or overdue.\(suffix)",
            payload: ProactiveNotificationPayload(destination: .actionItems, eventID: nil)
        )
    }

    static func postNavigation(destinationRawValue: String, eventID: String?) {
        guard let destination = ProactiveNotificationPayload.Destination(rawValue: destinationRawValue) else {
            return
        }

        let name: Notification.Name
        switch destination {
        case .calendar:
            name = .lidiaOpenHomeWorkspace
        case .actionItems:
            name = .lidiaOpenActionItemsWorkspace
        }

        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [
                destinationUserInfoKey: destinationRawValue,
                eventIDUserInfoKey: eventID ?? "",
            ]
        )
    }

    private static func send(
        category: Category,
        title: String,
        body: String,
        payload: ProactiveNotificationPayload
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue
        content.userInfo = [
            destinationUserInfoKey: payload.destination.rawValue,
            eventIDUserInfoKey: payload.eventID ?? "",
        ]

        let request = UNNotificationRequest(
            identifier: "lidia.proactive.\(category.rawValue).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension Notification.Name {
    static let lidiaOpenHomeWorkspace = Notification.Name("lidia.openHomeWorkspace")
    static let lidiaOpenActionItemsWorkspace = Notification.Name("lidia.openActionItemsWorkspace")
}
