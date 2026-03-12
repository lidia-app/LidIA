import Foundation
import os.log

enum ClickUpClient {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "ClickUpClient")
    private static let baseURL = "https://api.clickup.com/api/v2"

    static func createTask(
        title: String,
        description: String,
        listID: String,
        apiKey: String
    ) async throws {
        guard let url = URL(string: "\(baseURL)/list/\(listID)/task") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "name": title,
            "description": description,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            logger.error("ClickUp: task creation failed with HTTP \(http.statusCode)")
            throw URLError(.badServerResponse)
        }
        logger.info("ClickUp: task created successfully")
    }
}
