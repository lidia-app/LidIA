import Foundation

// MARK: - OpenAI Request/Response Types

private struct OpenAIChatRequest: Codable, Sendable {
    let model: String
    let messages: [LLMChatMessage]
    var response_format: ResponseFormat?
    var temperature: Float?

    struct ResponseFormat: Codable, Sendable {
        let type: String
    }
}

private struct OpenAIChatResponse: Codable, Sendable {
    let id: String
    let choices: [Choice]

    struct Choice: Codable, Sendable {
        let message: LLMChatMessage
        let finish_reason: String?
    }
}

private struct OpenAIStreamChatRequest: Codable, Sendable {
    let model: String
    let messages: [LLMChatMessage]
    let stream: Bool
}

private struct OpenAIStreamChunk: Codable, Sendable {
    let choices: [StreamChoice]

    struct StreamChoice: Codable, Sendable {
        let delta: Delta
        let finish_reason: String?

        struct Delta: Codable, Sendable {
            let content: String?
        }
    }
}

private struct OpenAIModelsResponse: Codable, Sendable {
    let data: [Model]

    struct Model: Codable, Sendable {
        let id: String
    }
}

// MARK: - OpenAIClient

actor OpenAIClient: LLMClient {
    let apiKey: String
    let baseURL: URL
    let timeoutInterval: TimeInterval
    let skipModelFilter: Bool

    init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!, timeoutInterval: TimeInterval = 120, skipModelFilter: Bool = false) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.skipModelFilter = skipModelFilter
    }

    private static let chatModelPrefixes = ["gpt-", "o1", "o3", "o4", "claude"]

    func listModels() async throws -> [String] {
        do {
            let url = baseURL.appendingPathComponent("models")
            var urlRequest = URLRequest(url: url)
            urlRequest.timeoutInterval = timeoutInterval
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let request = urlRequest

            let (data, response) = try await withRetry {
                try await URLSession.shared.data(for: request)
            }
            try validateResponse(response, data: data)

            let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            let models = modelsResponse.data.map(\.id)
            if skipModelFilter {
                return models.sorted()
            }
            return models
                .filter { id in
                    Self.chatModelPrefixes.contains { id.hasPrefix($0) }
                }
                .sorted()
        } catch {
            // If custom endpoint doesn't support /v1/models (e.g. NVIDIA NIM),
            // return empty — the user can type model names manually
            if baseURL.host != "api.openai.com" {
                return []
            }
            throw error
        }
    }

    func chat(messages: [LLMChatMessage], model: String, format: LLMResponseFormat?) async throws -> String {
        if apiKey.isEmpty {
            throw LLMError.authenticationError("API key not configured. Open Settings and enter your API key.")
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var request = OpenAIChatRequest(
            model: model,
            messages: messages
        )
        if case .json = format {
            request.response_format = .init(type: "json_object")
            request.temperature = LLMTemperature.structured
        }

        urlRequest.httpBody = try JSONEncoder().encode(request)
        let preparedRequest = urlRequest

        let (data, response) = try await withRetry {
            try await URLSession.shared.data(for: preparedRequest)
        }
        try validateResponse(response, data: data)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let firstChoice = chatResponse.choices.first else {
            throw LLMError.invalidResponse("OpenAI API returned no choices")
        }
        return firstChoice.message.content
    }

    func chatStream(messages: [LLMChatMessage], model: String) async -> AsyncThrowingStream<String, Error> {
        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let request = OpenAIStreamChatRequest(
            model: model,
            messages: messages,
            stream: true
        )

        // Encode body before closure to avoid capturing mutable var
        let encodedBody: Data
        do {
            encodedBody = try JSONEncoder().encode(request)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        urlRequest.httpBody = encodedBody
        let preparedRequest = urlRequest

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: preparedRequest)
                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        throw LLMError.httpError(statusCode: httpResponse.statusCode, message: nil)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            break
                        }
                        guard let chunkData = payload.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: chunkData)
                        if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private struct OpenAIErrorResponse: Codable {
        let error: ErrorBody

        struct ErrorBody: Codable {
            let message: String
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error.message
            throw LLMError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

// OpenAIError removed — all providers now use unified LLMError (see LLMError.swift)
