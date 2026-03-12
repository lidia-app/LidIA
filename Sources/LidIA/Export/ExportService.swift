import AppKit

enum ExportService {
    static func meetingToMarkdown(_ meeting: Meeting) -> String {
        var md = "# \(meeting.title)\n\n"
        md += "**Date:** \(meeting.date.formatted(date: .complete, time: .shortened))\n"
        md += "**Duration:** \(formatDuration(meeting.duration))\n"

        if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
            md += "**Attendees:** \(attendees.joined(separator: ", "))\n"
        }

        md += "\n## Summary\n\n\(meeting.summary)\n"

        if !meeting.actionItems.isEmpty {
            md += "\n## Action Items\n\n"
            for item in meeting.actionItems {
                let check = item.isCompleted ? "[x]" : "[ ]"
                md += "- \(check) \(item.title)"
                if let assignee = item.assignee { md += " → \(assignee)" }
                if let deadline = item.displayDeadline { md += " (due: \(deadline))" }
                md += "\n"
            }
        }

        if !meeting.refinedTranscript.isEmpty {
            md += "\n## Transcript\n\n\(meeting.refinedTranscript)\n"
        }

        return md
    }

    static func summaryToMarkdown(_ meeting: Meeting) -> String {
        var md = "# \(meeting.title)\n\n"
        md += "**Date:** \(meeting.date.formatted(date: .complete, time: .shortened))\n"
        md += "**Duration:** \(formatDuration(meeting.duration))\n"

        if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
            md += "**Attendees:** \(attendees.joined(separator: ", "))\n"
        }

        md += "\n\(meeting.summary)\n"

        if !meeting.actionItems.isEmpty {
            md += "\n## Action Items\n\n"
            for item in meeting.actionItems {
                let check = item.isCompleted ? "[x]" : "[ ]"
                md += "- \(check) \(item.title)"
                if let assignee = item.assignee { md += " → \(assignee)" }
                if let deadline = item.displayDeadline { md += " (due: \(deadline))" }
                md += "\n"
            }
        }

        return md
    }

    static func actionItemsToMarkdown(_ meeting: Meeting) -> String {
        meeting.actionItems.map { item in
            let check = item.isCompleted ? "[x]" : "[ ]"
            var line = "- \(check) \(item.title)"
            if let assignee = item.assignee { line += " → \(assignee)" }
            if let deadline = item.displayDeadline { line += " (due: \(deadline))" }
            return line
        }.joined(separator: "\n")
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
