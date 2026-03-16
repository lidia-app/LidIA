import Foundation
import os.log

/// Fire-and-forget webhook client for n8n workflow automation.
actor N8nClient {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "N8nClient")

    struct AttendeeContext: Encodable, Sendable {
        let email: String
        let openActionItems: Int
        let overdueActionItems: Int
        let lastMeetingDate: String?
        let totalMeetings: Int
    }

    struct ActionItemPayload: Encodable, Sendable {
        var title: String
        var assignee: String?
        var deadline: String?
        var priority: String? = nil
        var suggestedDestination: String? = nil
    }

    struct WebhookPayload: Encodable, Sendable {
        var meetingTitle: String
        var date: String
        var duration: TimeInterval
        var summary: String
        var actionItems: [ActionItemPayload]
        var attendees: [String]
        var transcript: String
        var notes: String = ""
        var meetingType: String? = nil
        var attendeeContext: [AttendeeContext] = []
    }

    /// Sends a pre-built payload to the configured n8n webhook URL.
    /// This is fire-and-forget: errors are logged but never thrown.
    static func sendWebhook(
        payload: WebhookPayload,
        webhookURL: String,
        authHeader: String?
    ) async {
        guard let url = URL(string: webhookURL) else {
            logger.error("n8n: invalid webhook URL: \(webhookURL)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let auth = authHeader, !auth.isEmpty {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        do {
            let data = try JSONEncoder().encode(payload)
            request.httpBody = data

            let (_, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    logger.info("n8n: webhook sent successfully (HTTP \(http.statusCode))")
                } else {
                    logger.warning("n8n: webhook returned HTTP \(http.statusCode)")
                }
            }
        } catch {
            logger.error("n8n: webhook request failed: \(error.localizedDescription)")
        }
    }
}
