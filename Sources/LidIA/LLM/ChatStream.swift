import Foundation
import os

// MARK: - Chat Types

struct FileAttachment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let content: String

    init(id: UUID = UUID(), name: String, content: String) {
        self.id = id
        self.name = name
        self.content = content
    }
}

struct ChatBarMessage: Identifiable, Codable, Sendable, Equatable {
    enum GroundingConfidence: String, Codable, Sendable {
        case low
        case medium
        case high

        var displayLabel: String {
            switch self {
            case .low: return "Low confidence"
            case .medium: return "Medium confidence"
            case .high: return "High confidence"
            }
        }
    }

    let id: UUID
    let role: Role
    var text: String
    let attachments: [FileAttachment]
    let sourceMeetings: [String]
    let groundingConfidence: GroundingConfidence?

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        attachments: [FileAttachment] = [],
        sourceMeetings: [String] = [],
        groundingConfidence: GroundingConfidence? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.sourceMeetings = sourceMeetings
        self.groundingConfidence = groundingConfidence
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case attachments
        case sourceMeetings
        case groundingConfidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decodeIfPresent(Role.self, forKey: .role) ?? .assistant
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        attachments = try container.decodeIfPresent([FileAttachment].self, forKey: .attachments) ?? []
        sourceMeetings = try container.decodeIfPresent([String].self, forKey: .sourceMeetings) ?? []
        groundingConfidence = try container.decodeIfPresent(GroundingConfidence.self, forKey: .groundingConfidence)
    }
}

// MARK: - ChatStream Protocol

@MainActor
protocol ChatStream: AnyObject {
    func send(
        _ message: String,
        history: [LLMChatMessage],
        context: String,
        attachments: [FileAttachment],
        model: String
    ) -> AsyncStream<String>

    func reset()
}

// MARK: - HTTPChatStream

@MainActor
final class HTTPChatStream: ChatStream {
    private let settings: AppSettings
    private let modelManager: ModelManager?

    init(settings: AppSettings, modelManager: ModelManager? = nil) {
        self.settings = settings
        self.modelManager = modelManager
    }

    func send(
        _ message: String,
        history: [LLMChatMessage],
        context: String,
        attachments: [FileAttachment],
        model: String
    ) -> AsyncStream<String> {
        // Build messages array
        var messages: [LLMChatMessage] = []

        // System prompt with meeting context and date
        let dateString = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let personalization = VoiceToolExecutor.personalizationPrompt(settings: settings)
        let systemPrompt = """
            You are LidIA, an intelligent meeting assistant. Today is \(dateString).
            \(personalization)
            When the user asks about "my" action items, tasks, or responsibilities, match against action items assigned to the user (look for their name in the assignee field, or items without an explicit assignee from meetings they attended).

            Use the following meeting context to answer the user's question:

            \(context)

            Response style:
            - Be concise. 1-3 sentences for simple requests. No filler, no preamble.
            - For action requests (create, complete, edit, delete), confirm briefly and stop. Do NOT elaborate, explain why it's a good idea, or ask follow-up questions unless truly ambiguous.
            - For questions, answer directly. Reference specific meeting titles when possible.
            - Never use emojis. Never output XML tags or JSON tool calls.
            - Base answers only on the provided meeting context.
            - If the context is insufficient, start your response with "Insufficient evidence:".
            """
        messages.append(LLMChatMessage(role: "system", content: systemPrompt))

        // Prepend file attachment content as user messages
        for attachment in attachments {
            messages.append(LLMChatMessage(
                role: "user",
                content: "File: \(attachment.name)\n\n\(attachment.content)"
            ))
        }

        // Append conversation history
        messages.append(contentsOf: history)

        // Append the new user message
        messages.append(LLMChatMessage(role: "user", content: message))

        let capturedMessages = messages
        let capturedSettings = settings
        let capturedModelManager = modelManager

        return AsyncStream { continuation in
            Task { @MainActor in
                let primaryClient = makeLLMClient(settings: capturedSettings, modelManager: capturedModelManager)
                do {
                    for try await token in await primaryClient.chatStream(messages: capturedMessages, model: model) {
                        continuation.yield(token)
                    }
                    continuation.finish()
                    return
                } catch {
                    // Attempt fallback if configured
                    guard let fallbackProviderEnum = AppSettings.LLMProvider(rawValue: capturedSettings.fallbackProvider),
                          fallbackProviderEnum != capturedSettings.llmProvider,
                          let fallbackClient = makeClientForProvider(fallbackProviderEnum, settings: capturedSettings, modelManager: capturedModelManager) else {
                        continuation.yield("[Error: \(error.localizedDescription)]")
                        continuation.finish()
                        return
                    }

                    let fallbackModel = capturedSettings.fallbackModel.isEmpty
                        ? defaultModelForProvider(fallbackProviderEnum, settings: capturedSettings)
                        : capturedSettings.fallbackModel

                    fallbackLogger.info("Chat stream falling back to \(fallbackProviderEnum.rawValue)")

                    do {
                        for try await token in await fallbackClient.chatStream(messages: capturedMessages, model: fallbackModel) {
                            continuation.yield(token)
                        }
                    } catch let fallbackError {
                        continuation.yield("[Error: \(fallbackError.localizedDescription)]")
                    }
                    continuation.finish()
                }
            }
        }
    }

    func reset() {
        // No persistent state to clear in the HTTP implementation
    }
}
