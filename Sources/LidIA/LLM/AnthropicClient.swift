import Foundation

// MARK: - Anthropic Request/Response Types

private struct AnthropicRequest: Codable, Sendable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [AnthropicMessage]

    struct AnthropicMessage: Codable, Sendable {
        let role: String
        let content: String
    }
}

private struct AnthropicResponse: Codable, Sendable {
    let id: String
    let content: [ContentBlock]
    let stop_reason: String?

    struct ContentBlock: Codable, Sendable {
        let type: String
        let text: String?
    }
}

private struct AnthropicModelsResponse: Codable, Sendable {
    let data: [Model]

    struct Model: Codable, Sendable {
        let id: String
    }
}

// MARK: - AnthropicClient

actor AnthropicClient: LLMClient {
    let apiKey: String
    let baseURL: URL
    let timeoutInterval: TimeInterval

    init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com")!, timeoutInterval: TimeInterval = 120) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
    }

    func listModels() async throws -> [String] {
        // Try API first with required beta header
        do {
            let url = baseURL.appendingPathComponent("v1/models")
            var urlRequest = URLRequest(url: url)
            urlRequest.timeoutInterval = timeoutInterval
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            urlRequest.setValue("models-2025-04-15", forHTTPHeaderField: "anthropic-beta")
            let request = urlRequest

            let (data, response) = try await withRetry {
                try await URLSession.shared.data(for: request)
            }
            try validateResponse(response, data: data)

            let modelsResponse = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            return modelsResponse.data
                .map(\.id)
                .filter { $0.hasPrefix("claude") }
                .sorted()
        } catch {
            // Fallback to known models if API fails
            return [
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-haiku-4-5-20251001",
                "claude-sonnet-4-5-20250514",
            ]
        }
    }

    func chat(messages: [LLMChatMessage], model: String, format: LLMResponseFormat?) async throws -> String {
        if apiKey.isEmpty {
            throw LLMError.authenticationError("API key not configured. Open Settings and enter your Anthropic API key.")
        }

        let url = baseURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Extract system message if present
        var systemPrompt: String?
        var chatMessages: [AnthropicRequest.AnthropicMessage] = []

        for msg in messages {
            if msg.role == "system" {
                systemPrompt = msg.content
            } else {
                chatMessages.append(.init(role: msg.role, content: msg.content))
            }
        }

        // If format is JSON, append instruction to system prompt
        if case .json = format {
            let jsonInstruction = "\n\nRespond ONLY with valid JSON, no markdown fences."
            systemPrompt = (systemPrompt ?? "") + jsonInstruction
        }

        let request = AnthropicRequest(
            model: model,
            max_tokens: 4096,
            system: systemPrompt,
            messages: chatMessages
        )

        urlRequest.httpBody = try JSONEncoder().encode(request)
        let preparedRequest = urlRequest

        let (data, response) = try await withRetry {
            try await URLSession.shared.data(for: preparedRequest)
        }
        try validateResponse(response, data: data)

        let anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = anthropicResponse.content.first(where: { $0.type == "text" })?.text else {
            throw LLMError.invalidResponse("Anthropic API returned no content")
        }
        return text
    }

    private struct AnthropicErrorResponse: Codable {
        let error: ErrorBody

        struct ErrorBody: Codable {
            let message: String
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data))?.error.message
            throw LLMError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

// AnthropicError removed — all providers now use unified LLMError (see LLMError.swift)
