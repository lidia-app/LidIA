import Foundation
import SwiftData

// MARK: - SwiftData Models for Chat Persistence

@Model
final class ChatThreadModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var scopeRawValue: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessageModel.thread)
    var messages: [ChatMessageModel]

    init(
        id: UUID = UUID(),
        title: String,
        scopeRawValue: String = "All meetings",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [ChatMessageModel] = []
    ) {
        self.id = id
        self.title = title
        self.scopeRawValue = scopeRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

@Model
final class ChatMessageModel {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var timestamp: Date

    /// Serialized JSON for source meetings and grounding confidence.
    var sourceMeetingsJSON: String?
    var groundingConfidenceRawValue: String?
    /// Serialized JSON for file attachments.
    var attachmentsJSON: String?

    var thread: ChatThreadModel?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = .now,
        sourceMeetingsJSON: String? = nil,
        groundingConfidenceRawValue: String? = nil,
        attachmentsJSON: String? = nil,
        thread: ChatThreadModel? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.sourceMeetingsJSON = sourceMeetingsJSON
        self.groundingConfidenceRawValue = groundingConfidenceRawValue
        self.attachmentsJSON = attachmentsJSON
        self.thread = thread
    }
}
