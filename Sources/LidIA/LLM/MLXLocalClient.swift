import Foundation
import MLX
@preconcurrency import MLXLMCommon
import MLXLLM
import os

// MARK: - MLXLocalError

enum MLXLocalError: LocalizedError {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No MLX model is currently loaded. Please download and load a model first."
        }
    }
}

// MARK: - MLXLocalClient

/// Local MLX inference client using the framework's managed `generate()` API.
///
/// @unchecked Sendable is safe: `modelManager` is @MainActor-isolated and only
/// accessed via `await MainActor.run { }` blocks.
final class MLXLocalClient: LLMClient, @unchecked Sendable {

    private static let logger = Logger(subsystem: "io.lidia.app", category: "MLXLocalClient")

    private let modelManager: ModelManager

    @MainActor
    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - LLMClient

    func listModels() async throws -> [String] {
        await MainActor.run {
            ModelManager.availableModels.map(\.id)
        }
    }

    func chat(messages: [LLMChatMessage], model: String, format: LLMResponseFormat?) async throws -> String {
        let container = try await getContainer()
        let userInput = buildUserInput(from: messages)

        let temp: Float = (format == .json) ? LLMTemperature.structured : LLMTemperature.chat
        let parameters = GenerateParameters(
            maxTokens: 16384,
            temperature: temp,
            repetitionPenalty: 1.1,
            repetitionContextSize: 64
        )

        let output: String = try await container.perform { context in
            let lmInput = try await context.processor.prepare(input: userInput)

            let stream = try generate(
                input: lmInput,
                parameters: parameters,
                context: context
            )

            var fullText = ""
            for await generation in stream {
                switch generation {
                case .chunk(let text):
                    fullText += text
                case .info, .toolCall:
                    break
                }
            }
            return fullText
        }

        let cleaned = stripThinking(output)
        Self.logger.info("MLX generation complete: \(cleaned.count) chars")
        return cleaned
    }

    func chatStream(messages: [LLMChatMessage], model: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await self.getContainer()
                    nonisolated(unsafe) let userInput = self.buildUserInput(from: messages)

                    let parameters = GenerateParameters(
                        maxTokens: 16384,
                        temperature: LLMTemperature.chat,
                        repetitionPenalty: 1.1,
                        repetitionContextSize: 64
                    )

                    try await container.perform { context in
                        let lmInput = try await context.processor.prepare(input: userInput)

                        let stream = try generate(
                            input: lmInput,
                            parameters: parameters,
                            context: context
                        )

                        var buffer = ""
                        var thinkingDone = false

                        for await generation in stream {
                            if Task.isCancelled { break }
                            switch generation {
                            case .chunk(let text):
                                if thinkingDone {
                                    continuation.yield(text)
                                } else {
                                    buffer += text
                                    if let range = buffer.range(of: "</think>") {
                                        thinkingDone = true
                                        let afterThink = String(buffer[range.upperBound...])
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !afterThink.isEmpty {
                                            continuation.yield(afterThink)
                                        }
                                        buffer = ""
                                    }
                                }
                            case .info:
                                break
                            case .toolCall:
                                break
                            }
                        }

                        // If model never emitted <think> tags, strip plain-text thinking
                        if !thinkingDone && !buffer.isEmpty {
                            let stripped = self.stripThinking(buffer)
                            continuation.yield(stripped)
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

    // MARK: - Private

    private func getContainer() async throws -> ModelContainer {
        if let container = await MainActor.run(body: { modelManager.modelContainer }) {
            return container
        }

        let modelID: String? = await MainActor.run {
            let settings = AppSettings()
            if !settings.selectedMLXModelID.isEmpty, modelManager.isDownloaded(settings.selectedMLXModelID) {
                return settings.selectedMLXModelID
            }
            return modelManager.downloadedModels.first?.id
        }

        if let modelID {
            Self.logger.info("Auto-loading MLX model: \(modelID)")
            try await modelManager.loadModel(modelID)
            if let container = await MainActor.run(body: { modelManager.modelContainer }) {
                return container
            }
        }

        throw MLXLocalError.noModelLoaded
    }

    /// Strip thinking/reasoning blocks from model output.
    private func stripThinking(_ text: String) -> String {
        if let range = text.range(of: "</think>") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Thinking Process") || trimmed.hasPrefix("**Thinking") {
            if let jsonStart = trimmed.firstIndex(of: "{") {
                return String(trimmed[jsonStart...])
            }
        }
        return text
    }

    private func buildUserInput(from messages: [LLMChatMessage]) -> UserInput {
        let chatMessages = messages.compactMap { msg -> Chat.Message? in
            switch msg.role {
            case "system": return .system(msg.content)
            case "user": return .user(msg.content)
            case "assistant": return .assistant(msg.content)
            case "tool": return .tool(msg.content)
            default: return .user(msg.content)
            }
        }
        return UserInput(chat: chatMessages)
    }
}
