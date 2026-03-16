import Foundation

@MainActor
enum VaultExporter {
    /// Write a completed meeting as a Markdown file with YAML frontmatter.
    static func export(meeting: Meeting, settings: AppSettings) throws {
        guard settings.vaultExportEnabled else { return }

        let expandedPath = NSString(string: settings.vaultExportPath).expandingTildeInPath
        let vaultURL = URL(fileURLWithPath: expandedPath)

        // Create directory if needed
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        // Build filename: "2026-03-13 — Team Standup.md"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: meeting.date)
        let safeTitle = meeting.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let filename = "\(dateStr) — \(safeTitle.isEmpty ? "Untitled" : safeTitle).md"
        let fileURL = vaultURL.appendingPathComponent(filename)

        // Build YAML frontmatter
        var frontmatter = """
        ---
        title: "\(meeting.title)"
        date: \(ISO8601DateFormatter().string(from: meeting.date))
        duration: \(Int(meeting.duration))
        status: \(meeting.status.rawValue)
        """

        if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
            frontmatter += "\nattendees:\n"
            for a in attendees {
                frontmatter += "  - \"\(a)\"\n"
            }
        }

        if !meeting.actionItems.isEmpty {
            frontmatter += "action_items: \(meeting.actionItems.count)\n"
        }

        if let eventID = meeting.calendarEventID {
            frontmatter += "calendar_event_id: \"\(eventID)\"\n"
        }

        frontmatter += "---\n\n"

        // Build body
        var body = ""

        // Summary
        let summary = meeting.userEditedSummary ?? meeting.summary
        if !summary.isEmpty {
            body += summary + "\n\n"
        }

        // Action items
        let openItems = meeting.actionItems.filter { !$0.isCompleted }
        let doneItems = meeting.actionItems.filter { $0.isCompleted }
        if !meeting.actionItems.isEmpty {
            body += "## Action Items\n\n"
            for item in openItems {
                let assignee = item.assignee.map { " @\($0)" } ?? ""
                let deadline = item.displayDeadline.map { " (due: \($0))" } ?? ""
                let priority = item.priority != "none" ? " [\(item.priority)]" : ""
                body += "- [ ] \(item.title)\(assignee)\(deadline)\(priority)\n"
            }
            for item in doneItems {
                body += "- [x] \(item.title)\n"
            }
            body += "\n"
        }

        // Notes
        if !meeting.notes.isEmpty {
            body += "## Notes\n\n\(meeting.notes)\n\n"
        }

        // Transcript (optional)
        if settings.vaultExportIncludeTranscript {
            let transcript = meeting.userEditedTranscript ?? meeting.refinedTranscript
            if !transcript.isEmpty {
                body += "## Transcript\n\n\(transcript)\n"
            }
        }

        let content = frontmatter + body
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
