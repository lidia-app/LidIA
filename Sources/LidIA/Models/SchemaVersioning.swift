import Foundation
import SwiftData

// MARK: - Current Schema

/// Current schema version. SwiftData handles lightweight migrations automatically
/// (adding nullable properties, indexes, external storage) without needing an
/// explicit migration plan when all changes are additive.
enum AppSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 2, 0)

    static var models: [any PersistentModel.Type] {
        [Meeting.self, ActionItem.self, TalkingPoint.self, ChatThreadModel.self, ChatMessageModel.self]
    }
}
