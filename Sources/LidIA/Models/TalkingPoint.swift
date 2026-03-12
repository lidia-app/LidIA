import Foundation
import SwiftData

@Model
final class TalkingPoint {
    var id: UUID
    var personIdentifier: String
    var content: String
    var createdDate: Date
    var isUsed: Bool

    init(
        personIdentifier: String,
        content: String,
        createdDate: Date = .now,
        isUsed: Bool = false
    ) {
        self.id = UUID()
        self.personIdentifier = personIdentifier
        self.content = content
        self.createdDate = createdDate
        self.isUsed = isUsed
    }
}
