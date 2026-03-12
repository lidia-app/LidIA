import Foundation
import os
import SwiftData
import UserNotifications

@MainActor
@Observable
final class WeeklyDigestService {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "WeeklyDigest")
    private var digestTask: Task<Void, Never>?

    func startScheduler(settings: AppSettings, modelContext: ModelContext) {
        guard settings.proactiveMorningDigest else {
            digestTask?.cancel()
            digestTask = nil
            return
        }

        digestTask?.cancel()
        digestTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled else { return }

                let now = Date()
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: now)
                let weekday = calendar.component(.weekday, from: now)

                // Monday at 9am
                if weekday == 2, hour == 9 {
                    Self.logger.info("Generating weekly digest")
                    let digest = generateDigest(modelContext: modelContext)
                    sendDigestNotification(digest: digest)
                }
            }
        }
    }

    func stopScheduler() {
        digestTask?.cancel()
        digestTask = nil
    }

    // MARK: - Digest Generation

    func generateDigest(modelContext: ModelContext) -> WeeklyDigest {
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: .now)!

        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let allMeetings = try? modelContext.fetch(descriptor) else {
            return WeeklyDigest(meetings: [], openItems: [], completedItems: [])
        }

        let weekMeetings = allMeetings.filter {
            $0.status == .complete && $0.date >= oneWeekAgo
        }

        let allItems = allMeetings.flatMap(\.actionItems)
        let openItems = allItems.filter { !$0.isCompleted }
        let completedThisWeek = allItems.filter { $0.isCompleted }

        return WeeklyDigest(
            meetings: weekMeetings,
            openItems: openItems,
            completedItems: completedThisWeek
        )
    }

    func formatDigestMarkdown(_ digest: WeeklyDigest) -> String {
        var md = "## Weekly Meeting Digest\n\n"
        md += "**\(digest.meetings.count)** meetings this week · "
        md += "**\(digest.completedItems.count)** items completed · "
        md += "**\(digest.openItems.count)** still open\n\n"

        // Meetings by day
        if !digest.meetings.isEmpty {
            md += "### Meetings\n"
            for meeting in digest.meetings {
                let time = meeting.date.formatted(date: .abbreviated, time: .shortened)
                let duration = meeting.duration > 0
                    ? " (\(Int(meeting.duration / 60))min)"
                    : ""
                md += "- **\(meeting.title)**\(duration) — \(time)\n"

                // Summary snippet (first 120 chars)
                let summary = meeting.userEditedSummary ?? meeting.summary
                if !summary.isEmpty {
                    let snippet = String(summary.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                    md += "  _\(snippet)..._\n"
                }
            }
            md += "\n"
        }

        // Open action items
        if !digest.openItems.isEmpty {
            md += "### Open Action Items\n"
            for item in digest.openItems.prefix(15) {
                md += "- \(item.title)"
                if let assignee = item.assignee, !assignee.isEmpty { md += " → **\(assignee)**" }
                if let deadline = item.displayDeadline { md += " (due: \(deadline))" }
                md += "\n"
            }
            if digest.openItems.count > 15 {
                md += "- _...and \(digest.openItems.count - 15) more_\n"
            }
            md += "\n"
        }

        // Completed this week
        if !digest.completedItems.isEmpty {
            md += "### Completed This Week\n"
            for item in digest.completedItems.prefix(10) {
                md += "- ~~\(item.title)~~"
                if let assignee = item.assignee, !assignee.isEmpty { md += " — \(assignee)" }
                md += "\n"
            }
        }

        return md
    }

    // MARK: - Notification

    private func sendDigestNotification(digest: WeeklyDigest) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let meetingCount = digest.meetings.count
        let openCount = digest.openItems.count

        let content = UNMutableNotificationContent()
        content.title = "Weekly Digest"
        content.body = "\(meetingCount) meeting\(meetingCount == 1 ? "" : "s") this week, \(openCount) open action item\(openCount == 1 ? "" : "s")"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lidia.weekly-digest.\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        Self.logger.info("Weekly digest notification sent: \(meetingCount) meetings, \(openCount) open items")
    }
}

// MARK: - Digest Model

struct WeeklyDigest {
    let meetings: [Meeting]
    let openItems: [ActionItem]
    let completedItems: [ActionItem]
}
