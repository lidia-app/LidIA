import Foundation
import SwiftData

@Model
final class ActionItem {
    var id: UUID
    var title: String
    var assignee: String?
    var deadline: String?
    var deadlineDate: Date?
    var isCompleted: Bool
    var notionBlockID: String?
    var notionTaskPageID: String?
    var reminderID: String?
    /// Verbatim quote from transcript that sourced this action item. Used for transcript linking.
    var sourceQuote: String?
    /// Priority: "critical", "high", "medium", "low", "none"
    var priority: String = "none"
    /// LLM-suggested destination: "clickup", "notion", "reminder", "n8n", "none"
    var suggestedDestination: String?
    /// User-confirmed destination (same values as suggestedDestination)
    var confirmedDestination: String?
    @Relationship var meeting: Meeting?

    init(
        title: String,
        assignee: String? = nil,
        deadline: String? = nil,
        deadlineDate: Date? = nil,
        isCompleted: Bool = false,
        notionBlockID: String? = nil,
        notionTaskPageID: String? = nil,
        reminderID: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.assignee = assignee
        self.deadline = deadline
        self.deadlineDate = deadlineDate
        self.isCompleted = isCompleted
        self.notionBlockID = notionBlockID
        self.notionTaskPageID = notionTaskPageID
        self.reminderID = reminderID
    }

    var isAutoUrgent: Bool {
        guard let deadlineDate, !isCompleted else { return false }
        return deadlineDate.timeIntervalSinceNow <= 48 * 3600
    }

    /// True for critical/high priority or auto-urgent (deadline ≤48h)
    var isUrgent: Bool {
        priority == "critical" || priority == "high" || isAutoUrgent
    }

    var priorityLevel: Int {
        switch priority {
        case "critical": 4
        case "high": 3
        case "medium": 2
        case "low": 1
        default: 0
        }
    }

    var displayDeadline: String? {
        if let deadlineDate {
            return Self.formattedDeadline(from: deadlineDate)
        }
        let trimmed = deadline?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    func setPreciseDeadline(_ date: Date?) {
        deadlineDate = date
        deadline = date.map(Self.formattedDeadline(from:))
    }

    static func formattedDeadline(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    #Index<ActionItem>([\.isCompleted])
}
