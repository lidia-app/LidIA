import Foundation
import os

// MARK: - OpenAI WebSocket Realtime Stream

private let wsLogger = Logger(subsystem: "io.lidia.app", category: "OpenAIWebSocketStream")

@MainActor
final class OpenAIWebSocketStream: ChatStream {
    let apiKey: String
    let defaultModel: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var previousResponseID: String?

    init(apiKey: String, defaultModel: String = "gpt-4o") {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
    }

    // MARK: - ChatStream Conformance

    func send(
        _ message: String,
        history: [LLMChatMessage],
        context: String,
        attachments: [FileAttachment],
        model: String
    ) -> AsyncStream<String> {
        let resolvedModel = model.isEmpty ? defaultModel : model

        return AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                if self.webSocketTask == nil {
                    self.connect()
                }

                guard let ws = self.webSocketTask else {
                    continuation.finish()
                    return
                }

                // Build the response.create event
                let event = self.buildResponseCreateEvent(
                    message: message,
                    history: history,
                    context: context,
                    attachments: attachments,
                    model: resolvedModel
                )

                guard let jsonData = try? JSONSerialization.data(withJSONObject: event),
                      let jsonString = String(data: jsonData, encoding: .utf8)
                else {
                    wsLogger.error("Failed to serialize event JSON")
                    continuation.finish()
                    return
                }

                // Send the event
                do {
                    try await ws.send(.string(jsonString))
                } catch {
                    wsLogger.error("Send error: \(error)")
                    continuation.finish()
                    return
                }

                // Read response events in a loop
                await self.readEvents(from: ws, continuation: continuation)
            }
        }
    }

    func reset() {
        previousResponseID = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Private: Connection

    private func connect() {
        let url = URL(string: "wss://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        webSocketTask = task
    }

    // MARK: - Private: Event Building

    private func buildResponseCreateEvent(
        message: String,
        history: [LLMChatMessage],
        context: String,
        attachments: [FileAttachment],
        model: String
    ) -> [String: Any] {
        var event: [String: Any] = [
            "type": "response.create",
        ]

        var responseBody: [String: Any] = [
            "modalities": ["text"],
            "model": model,
        ]

        if let prevID = previousResponseID {
            // Continuation: reference previous response and send only the new user message
            responseBody["previous_response_id"] = prevID

            var inputItems: [[String: Any]] = []
            inputItems.append([
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": message]],
            ])

            responseBody["input"] = inputItems
        } else {
            // First message: include full context
            var inputItems: [[String: Any]] = []

            // System message with meeting context
            if !context.isEmpty {
                let dateString = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
                let systemPrompt = """
                You are LidIA, an intelligent meeting assistant. Today is \(dateString).

                Use the following meeting context to answer the user's question:

                \(context)

                Grounding rules:
                - Base answers only on the provided meeting context.
                - If the context is insufficient, start your response with "Insufficient evidence:".
                - Prefer concise answers that reference specific meeting titles when possible.
                """
                inputItems.append([
                    "type": "message",
                    "role": "system",
                    "content": [["type": "input_text", "text": systemPrompt]],
                ])
            }

            // History messages
            for msg in history {
                inputItems.append([
                    "type": "message",
                    "role": msg.role,
                    "content": [["type": "input_text", "text": msg.content]],
                ])
            }

            // Attachment messages
            for attachment in attachments {
                let text = "File: \(attachment.name)\n\n\(attachment.content)"
                inputItems.append([
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": text]],
                ])
            }

            // Current user message
            inputItems.append([
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": message]],
            ])

            responseBody["input"] = inputItems
        }

        event["response"] = responseBody
        return event
    }

    // MARK: - Private: Event Reading

    private nonisolated func readEvents(
        from ws: URLSessionWebSocketTask,
        continuation: AsyncStream<String>.Continuation
    ) async {
        while true {
            let result: URLSessionWebSocketTask.Message
            do {
                result = try await ws.receive()
            } catch {
                wsLogger.error("Receive error: \(error)")
                continuation.finish()
                return
            }

            guard case .string(let text) = result else {
                // Skip binary frames
                continue
            }

            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = json["type"] as? String
            else {
                continue
            }

            switch eventType {
            case "response.output_item.delta", "response.content_part.delta":
                // Extract delta text
                if let delta = json["delta"] as? [String: Any],
                   let deltaText = delta["text"] as? String
                {
                    continuation.yield(deltaText)
                }

            case "response.text.delta":
                // Alternative delta format
                if let delta = json["delta"] as? String {
                    continuation.yield(delta)
                }

            case "response.completed":
                // Save the response ID for future continuations
                if let response = json["response"] as? [String: Any],
                   let responseID = response["id"] as? String
                {
                    await MainActor.run { [weak self] in
                        self?.previousResponseID = responseID
                    }
                }
                continuation.finish()
                return

            case "error":
                if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    wsLogger.error("API error: \(message)")
                }
                continuation.finish()
                return

            default:
                // Skip unhandled event types (response.created, response.in_progress, etc.)
                break
            }
        }
    }
}
