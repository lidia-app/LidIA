import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "io.lidia.app", category: "ChatThreadStore")

/// Manages chat thread CRUD and persistence via SwiftData.
@MainActor
@Observable
final class ChatThreadStore {

    // MARK: - Public State

    /// In-memory thread list, kept in sync with SwiftData.
    var threads: [ChatBarViewModel.ChatThread] = []
    var activeThreadID: UUID?

    // MARK: - Private State

    private var modelContext: ModelContext?
    private var didLoadPersistedThreads = false

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadThreadsIfNeeded()
    }

    // MARK: - Computed

    var recentThreads: [ChatBarViewModel.ChatThread] {
        threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Thread Operations

    func openThread(_ thread: ChatBarViewModel.ChatThread) -> [ChatBarMessage] {
        activeThreadID = thread.id
        return thread.messages
    }

    func openThread(id: UUID) -> [ChatBarMessage]? {
        guard let thread = threads.first(where: { $0.id == id }) else { return nil }
        return openThread(thread)
    }

    func startNewThread() {
        activeThreadID = nil
    }

    func deleteThread(_ thread: ChatBarViewModel.ChatThread) {
        threads.removeAll { $0.id == thread.id }
        deleteThreadFromStore(id: thread.id)

        if activeThreadID == thread.id {
            activeThreadID = nil
        }
    }

    func ensureActiveThreadExists(initialPrompt: String, scope: ChatBarViewModel.ContextScope) {
        guard activeThreadID == nil else { return }
        let now = Date()
        let thread = ChatBarViewModel.ChatThread(
            title: ChatBarViewModel.makeThreadTitle(from: initialPrompt),
            scope: scope,
            createdAt: now,
            updatedAt: now,
            messages: []
        )
        threads.append(thread)
        activeThreadID = thread.id
        persistThread(thread)
    }

    func syncActiveThread(messages: [ChatBarMessage], scope: ChatBarViewModel.ContextScope) {
        guard let activeThreadID,
              let index = threads.firstIndex(where: { $0.id == activeThreadID }) else {
            return
        }

        threads[index].messages = messages
        threads[index].updatedAt = .now
        threads[index].scope = scope

        if threads[index].title == "New chat",
           let firstUser = messages.first(where: { $0.role == .user }) {
            threads[index].title = ChatBarViewModel.makeThreadTitle(from: firstUser.text)
        }

        persistThread(threads[index])
    }

    // MARK: - SwiftData Persistence

    private func loadThreadsIfNeeded() {
        guard !didLoadPersistedThreads else { return }
        didLoadPersistedThreads = true

        guard let modelContext else { return }

        // Migrate from UserDefaults if data exists there
        let legacyKey = "chatThreads.v1"
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let decoded = try? JSONDecoder().decode([ChatBarViewModel.ChatThread].self, from: data) {
            logger.info("Migrating \(decoded.count) chat threads from UserDefaults to SwiftData")
            for thread in decoded {
                let model = threadToModel(thread)
                modelContext.insert(model)
            }
            try? modelContext.save()
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }

        // Load from SwiftData
        do {
            let descriptor = FetchDescriptor<ChatThreadModel>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let models = try modelContext.fetch(descriptor)
            threads = models.map { modelToThread($0) }
        } catch {
            logger.error("Failed to load chat threads from SwiftData: \(error)")
        }
    }

    private func persistThread(_ thread: ChatBarViewModel.ChatThread) {
        guard let modelContext else { return }

        do {
            // Try to find existing model
            let threadID = thread.id
            var descriptor = FetchDescriptor<ChatThreadModel>(
                predicate: #Predicate { $0.id == threadID }
            )
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                // Update existing
                existing.title = thread.title
                existing.scopeRawValue = thread.scope.rawValue
                existing.updatedAt = thread.updatedAt

                // Replace messages: delete old ones, insert new ones
                for msg in existing.messages {
                    modelContext.delete(msg)
                }
                existing.messages = thread.messages.map { chatBarMsg in
                    messageToChatMessageModel(chatBarMsg, thread: existing)
                }
            } else {
                // Insert new
                let model = threadToModel(thread)
                modelContext.insert(model)
            }

            try modelContext.save()
        } catch {
            logger.error("Failed to persist chat thread: \(error)")
        }
    }

    private func deleteThreadFromStore(id: UUID) {
        guard let modelContext else { return }

        do {
            let descriptor = FetchDescriptor<ChatThreadModel>(
                predicate: #Predicate { $0.id == id }
            )
            let models = try modelContext.fetch(descriptor)
            for model in models {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to delete chat thread: \(error)")
        }
    }

    // MARK: - Conversion Helpers

    private func threadToModel(_ thread: ChatBarViewModel.ChatThread) -> ChatThreadModel {
        let model = ChatThreadModel(
            id: thread.id,
            title: thread.title,
            scopeRawValue: thread.scope.rawValue,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt
        )
        model.messages = thread.messages.map { chatBarMsg in
            messageToChatMessageModel(chatBarMsg, thread: model)
        }
        return model
    }

    private func messageToChatMessageModel(_ msg: ChatBarMessage, thread: ChatThreadModel) -> ChatMessageModel {
        let sourceMeetingsJSON: String?
        if !msg.sourceMeetings.isEmpty, let data = try? JSONEncoder().encode(msg.sourceMeetings) {
            sourceMeetingsJSON = String(data: data, encoding: .utf8)
        } else {
            sourceMeetingsJSON = nil
        }

        let attachmentsJSON: String?
        if !msg.attachments.isEmpty, let data = try? JSONEncoder().encode(msg.attachments) {
            attachmentsJSON = String(data: data, encoding: .utf8)
        } else {
            attachmentsJSON = nil
        }

        return ChatMessageModel(
            id: msg.id,
            role: msg.role.rawValue,
            content: msg.text,
            timestamp: .now,
            sourceMeetingsJSON: sourceMeetingsJSON,
            groundingConfidenceRawValue: msg.groundingConfidence?.rawValue,
            attachmentsJSON: attachmentsJSON,
            thread: thread
        )
    }

    private func modelToThread(_ model: ChatThreadModel) -> ChatBarViewModel.ChatThread {
        let scope = ChatBarViewModel.ContextScope(rawValue: model.scopeRawValue) ?? .allMeetings

        let sortedMessages = model.messages.sorted { $0.timestamp < $1.timestamp }
        let messages: [ChatBarMessage] = sortedMessages.map { msgModel in
            let role: ChatBarMessage.Role = msgModel.role == "user" ? .user : .assistant

            let sourceMeetings: [String]
            if let json = msgModel.sourceMeetingsJSON,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                sourceMeetings = decoded
            } else {
                sourceMeetings = []
            }

            let confidence: ChatBarMessage.GroundingConfidence?
            if let raw = msgModel.groundingConfidenceRawValue {
                confidence = ChatBarMessage.GroundingConfidence(rawValue: raw)
            } else {
                confidence = nil
            }

            let attachments: [FileAttachment]
            if let json = msgModel.attachmentsJSON,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([FileAttachment].self, from: data) {
                attachments = decoded
            } else {
                attachments = []
            }

            return ChatBarMessage(
                id: msgModel.id,
                role: role,
                text: msgModel.content,
                attachments: attachments,
                sourceMeetings: sourceMeetings,
                groundingConfidence: confidence
            )
        }

        return ChatBarViewModel.ChatThread(
            id: model.id,
            title: model.title,
            scope: scope,
            createdAt: model.createdAt,
            updatedAt: model.updatedAt,
            messages: messages
        )
    }
}
