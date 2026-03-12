import Foundation

actor NotionClient {
    enum NotionError: LocalizedError {
        case invalidResponse
        case requestFailed(statusCode: Int, message: String)
        case missingTitleProperty

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Notion returned an invalid response."
            case let .requestFailed(statusCode, message):
                return "Notion request failed (\(statusCode)): \(message)"
            case .missingTitleProperty:
                return "The selected Notion database does not have a title property."
            }
        }
    }

    struct TaskDatabaseSchema: Sendable {
        let titlePropertyName: String
        let datePropertyName: String?
        let checkboxPropertyName: String?
        let richTextPropertyName: String?
    }

    let apiKey: String
    private let baseURL = URL(string: "https://api.notion.com/v1")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - API Calls

    func listDatabases() async throws -> [(id: String, title: String)] {
        let url = baseURL.appendingPathComponent("search")
        let request = try makeRequest(
            url: url,
            method: "POST",
            body: ["filter": ["value": "database", "property": "object"]]
        )
        let json = try await performJSONRequest(request)
        let results = json["results"] as? [[String: Any]] ?? []

        return results.compactMap { db in
            guard let id = db["id"] as? String,
                  let titleArray = db["title"] as? [[String: Any]],
                  let text = titleArray.first?["plain_text"] as? String else { return nil }
            return (id: id, title: text)
        }
    }

    func createMeetingPage(
        databaseID: String,
        title: String,
        date: Date,
        duration: TimeInterval,
        bodyMarkdown: String
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("pages")
        let payload = Self.createPagePayload(
            databaseID: databaseID,
            title: title,
            date: date,
            duration: duration,
            bodyMarkdown: bodyMarkdown
        )
        let request = try makeRequest(url: url, method: "POST", body: payload)
        let json = try await performJSONRequest(request)
        return json["id"] as? String ?? ""
    }

    func fetchTaskDatabaseSchema(databaseID: String) async throws -> TaskDatabaseSchema {
        let url = baseURL.appendingPathComponent("databases").appendingPathComponent(databaseID)
        let request = try makeRequest(url: url, method: "GET")
        let json = try await performJSONRequest(request)
        let properties = json["properties"] as? [String: Any] ?? [:]

        func firstProperty(named type: String) -> String? {
            properties.first { _, value in
                (value as? [String: Any])?["type"] as? String == type
            }?.key
        }

        guard let titlePropertyName = firstProperty(named: "title") else {
            throw NotionError.missingTitleProperty
        }

        return TaskDatabaseSchema(
            titlePropertyName: titlePropertyName,
            datePropertyName: firstProperty(named: "date"),
            checkboxPropertyName: firstProperty(named: "checkbox"),
            richTextPropertyName: firstProperty(named: "rich_text")
        )
    }

    func createOrUpdateTaskPage(
        databaseID: String,
        existingPageID: String?,
        schema: TaskDatabaseSchema,
        title: String,
        deadline: Date?,
        deadlineText: String? = nil,
        isCompleted: Bool,
        meetingTitle: String
    ) async throws -> String {
        if let existingPageID, !existingPageID.isEmpty {
            let url = baseURL.appendingPathComponent("pages").appendingPathComponent(existingPageID)
            let payload = Self.updateTaskPagePayload(
                schema: schema,
                title: title,
                deadline: deadline,
                deadlineText: deadlineText,
                isCompleted: isCompleted,
                meetingTitle: meetingTitle
            )
            let request = try makeRequest(url: url, method: "PATCH", body: payload)
            let json = try await performJSONRequest(request)
            return json["id"] as? String ?? existingPageID
        }

        let url = baseURL.appendingPathComponent("pages")
        let payload = Self.createTaskPagePayload(
            databaseID: databaseID,
            schema: schema,
            title: title,
            deadline: deadline,
            deadlineText: deadlineText,
            isCompleted: isCompleted,
            meetingTitle: meetingTitle
        )
        let request = try makeRequest(url: url, method: "POST", body: payload)
        let json = try await performJSONRequest(request)
        return json["id"] as? String ?? ""
    }

    // MARK: - Payload Builders

    static func createPagePayload(
        databaseID: String,
        title: String,
        date: Date,
        duration: TimeInterval,
        bodyMarkdown: String
    ) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "parent": ["database_id": databaseID],
            "properties": [
                "Name": [
                    "title": [["text": ["content": title]]]
                ],
                "Date": [
                    "date": ["start": formatter.string(from: date)]
                ],
            ],
            "children": markdownToBlocks(bodyMarkdown),
        ]
    }

    static func createTaskPagePayload(
        databaseID: String,
        schema: TaskDatabaseSchema,
        title: String,
        deadline: Date?,
        deadlineText: String? = nil,
        isCompleted: Bool,
        meetingTitle: String
    ) -> [String: Any] {
        [
            "parent": ["database_id": databaseID],
            "properties": taskProperties(
                schema: schema,
                title: title,
                deadline: deadline,
                deadlineText: deadlineText,
                isCompleted: isCompleted,
                meetingTitle: meetingTitle
            ),
            "children": taskChildren(meetingTitle: meetingTitle, deadlineText: deadlineText, deadline: deadline),
        ]
    }

    static func updateTaskPagePayload(
        schema: TaskDatabaseSchema,
        title: String,
        deadline: Date?,
        deadlineText: String? = nil,
        isCompleted: Bool,
        meetingTitle: String
    ) -> [String: Any] {
        [
            "properties": taskProperties(
                schema: schema,
                title: title,
                deadline: deadline,
                deadlineText: deadlineText,
                isCompleted: isCompleted,
                meetingTitle: meetingTitle
            )
        ]
    }

    static func markdownToBlocks(_ markdown: String) -> [[String: Any]] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [[String: Any]] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                blocks.append([
                    "type": "heading_2",
                    "heading_2": [
                        "rich_text": [["type": "text", "text": ["content": text]]]
                    ],
                ])
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append([
                    "type": "bulleted_list_item",
                    "bulleted_list_item": [
                        "rich_text": [["type": "text", "text": ["content": text]]]
                    ],
                ])
            } else {
                blocks.append([
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [["type": "text", "text": ["content": String(trimmed)]]]
                    ],
                ])
            }
        }

        return blocks
    }

    // MARK: - Private

    private func makeRequest(url: URL, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func performJSONRequest(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await withRetry {
            try await URLSession.shared.data(for: request)
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NotionError.requestFailed(statusCode: httpResponse.statusCode, message: body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotionError.invalidResponse
        }
        return json
    }

    private static func taskProperties(
        schema: TaskDatabaseSchema,
        title: String,
        deadline: Date?,
        deadlineText: String? = nil,
        isCompleted: Bool,
        meetingTitle: String
    ) -> [String: Any] {
        var properties: [String: Any] = [
            schema.titlePropertyName: [
                "title": [["text": ["content": title]]]
            ]
        ]

        if let datePropertyName = schema.datePropertyName,
           let deadline {
            properties[datePropertyName] = [
                "date": ["start": iso8601String(from: deadline)]
            ]
        }

        if let checkboxPropertyName = schema.checkboxPropertyName {
            properties[checkboxPropertyName] = ["checkbox": isCompleted]
        }

        if let richTextPropertyName = schema.richTextPropertyName,
           !meetingTitle.isEmpty {
            properties[richTextPropertyName] = [
                "rich_text": [["type": "text", "text": ["content": meetingTitle]]]
            ]
        }

        return properties
    }

    private static func taskChildren(
        meetingTitle: String,
        deadlineText: String?,
        deadline: Date?
    ) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
        if !meetingTitle.isEmpty {
            blocks.append([
                "type": "paragraph",
                "paragraph": [
                    "rich_text": [[
                        "type": "text",
                        "text": ["content": "Source meeting: \(meetingTitle)"]
                    ]]
                ]
            ])
        }
        if deadline == nil, let deadlineText, !deadlineText.isEmpty {
            blocks.append([
                "type": "paragraph",
                "paragraph": [
                    "rich_text": [[
                        "type": "text",
                        "text": ["content": "Deadline: \(deadlineText)"]
                    ]]
                ]
            ])
        }
        return blocks
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
