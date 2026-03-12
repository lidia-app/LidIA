import Foundation
import os.log

/// Fire-and-forget Slack client for posting meeting summaries to a channel.
actor SlackClient {
    nonisolated private static let logger = Logger(subsystem: "io.lidia.app", category: "SlackClient")

    struct SlackMessage: Sendable {
        let channel: String
        let meetingTitle: String
        let date: Date
        let duration: TimeInterval
        let summary: String?
        let actionItems: [(title: String, assignee: String?, deadline: String?)]
        let attendees: [String]?
    }

    /// Posts a formatted meeting summary to the configured Slack channel.
    /// This is fire-and-forget: errors are logged but never thrown.
    static func postMeetingSummary(
        message: SlackMessage,
        botToken: String
    ) async {
        guard let url = URL(string: "https://slack.com/api/chat.postMessage") else {
            logger.error("Slack: invalid API URL")
            return
        }

        let blocks = buildBlocks(from: message)
        let fallbackText = "Meeting Summary: \(message.meetingTitle)"

        let body: [String: Any] = [
            "channel": message.channel,
            "text": fallbackText,
            "blocks": blocks
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let finalRequest = request

            let (data, response) = try await withRetry(policy: .networkDefault) {
                try await URLSession.shared.data(for: finalRequest)
            }

            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    // Slack API returns 200 even for errors; check "ok" field
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let ok = json["ok"] as? Bool {
                        if ok {
                            logger.info("Slack: message posted successfully")
                        } else {
                            let error = json["error"] as? String ?? "unknown"
                            logger.warning("Slack: API error — \(error)")
                        }
                    }
                } else {
                    logger.warning("Slack: HTTP \(http.statusCode)")
                }
            }
        } catch {
            logger.error("Slack: request failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Block Kit Builder

    private static func buildBlocks(from message: SlackMessage) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        // Header
        let dateStr = message.date.formatted(date: .abbreviated, time: .shortened)
        let minutes = Int(message.duration / 60)
        let durationStr = minutes > 0 ? "\(minutes) min" : "< 1 min"

        blocks.append([
            "type": "section",
            "text": [
                "type": "mrkdwn",
                "text": ":clipboard: *Meeting Summary: \(message.meetingTitle)*\n_\(dateStr) · \(durationStr)_"
            ]
        ])

        blocks.append(["type": "divider"])

        // Summary
        if let summary = message.summary, !summary.isEmpty {
            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*Summary*\n\(summary)"
                ]
            ])
        }

        // Action Items
        if !message.actionItems.isEmpty {
            let items = message.actionItems.map { item -> String in
                var line = "• \(item.title)"
                if let assignee = item.assignee, !assignee.isEmpty {
                    line += " — @\(assignee)"
                }
                if let deadline = item.deadline, !deadline.isEmpty {
                    line += " (due: \(deadline))"
                }
                return line
            }.joined(separator: "\n")

            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*Action Items*\n\(items)"
                ]
            ])
        }

        // Attendees
        if let attendees = message.attendees, !attendees.isEmpty {
            blocks.append([
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": "*Attendees*\n\(attendees.joined(separator: ", "))"
                ]
            ])
        }

        return blocks
    }
}
