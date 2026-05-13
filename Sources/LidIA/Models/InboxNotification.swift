import Foundation
import SwiftData

@Model
final class InboxNotification {
    var id: UUID = UUID()
    var type: String = "processed"    // "follow_up", "ticket", "processed", "reminder"
    var title: String = ""
    var body: String = ""
    var meetingID: UUID?
    var isRead: Bool = false
    var createdAt: Date = Date()
    var actionPayload: String?

    init(type: String, title: String, body: String, meetingID: UUID? = nil, actionPayload: String? = nil) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.body = body
        self.meetingID = meetingID
        self.createdAt = Date()
        self.isRead = false
        self.actionPayload = actionPayload
    }

    var typeIcon: String {
        switch type {
        case "follow_up": "pin.fill"
        case "ticket": "ticket.fill"
        case "processed": "checkmark.circle.fill"
        case "reminder": "clock.fill"
        case "meeting_prep": "doc.text.magnifyingglass"
        default: "bell.fill"
        }
    }

    // MARK: - Action Payload Parsing

    private struct ActionPayloadData: Codable {
        var draft: String?
        var recipient: String?
        var channel: String?
        var ticketTitle: String?
        var meetingTitle: String?
        var actionItemTitle: String?
        /// External event identifier — used by meeting_prep notifications to dedupe.
        var eventID: String?
    }

    private var parsedPayload: ActionPayloadData? {
        guard let json = actionPayload, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ActionPayloadData.self, from: data)
    }

    var draft: String? { parsedPayload?.draft }
    var recipient: String? { parsedPayload?.recipient }
    var channel: String? { parsedPayload?.channel }
    var ticketTitle: String? { parsedPayload?.ticketTitle }
    var sourceMeetingTitle: String? { parsedPayload?.meetingTitle }
    var sourceActionItemTitle: String? { parsedPayload?.actionItemTitle }
    var sourceEventID: String? { parsedPayload?.eventID }

    /// Whether this notification has a rich actionable payload (not just passive).
    var isDispatchable: Bool { draft != nil || channel != nil }

    /// Helper to create actionPayload JSON string from components.
    static func encodePayload(
        draft: String? = nil,
        recipient: String? = nil,
        channel: String? = nil,
        ticketTitle: String? = nil,
        meetingTitle: String? = nil,
        actionItemTitle: String? = nil,
        eventID: String? = nil
    ) -> String? {
        let payload = ActionPayloadData(
            draft: draft,
            recipient: recipient,
            channel: channel,
            ticketTitle: ticketTitle,
            meetingTitle: meetingTitle,
            actionItemTitle: actionItemTitle,
            eventID: eventID
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
