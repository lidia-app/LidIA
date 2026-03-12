import Foundation
import os.log

/// Fire-and-forget webhook client for n8n workflow automation.
actor N8nClient {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "N8nClient")

    struct WebhookPayload: Encodable, Sendable {
        let meetingTitle: String
        let date: String
        let duration: TimeInterval
        let summary: String
        let actionItems: [ActionItemPayload]
        let attendees: [String]
        let transcript: String
    }

    struct ActionItemPayload: Encodable, Sendable {
        let title: String
        let assignee: String?
        let deadline: String?
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
