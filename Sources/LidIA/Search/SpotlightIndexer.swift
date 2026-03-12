import CoreSpotlight
import Foundation
import os

enum SpotlightIndexer {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "SpotlightIndexer")
    static func indexMeeting(_ meeting: Meeting) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = meeting.title
        attributeSet.contentDescription = meeting.summary
        attributeSet.keywords = meeting.calendarAttendees
        attributeSet.contentCreationDate = meeting.date

        let item = CSSearchableItem(
            uniqueIdentifier: meeting.id.uuidString,
            domainIdentifier: "com.lidia.meetings",
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                logger.error("Spotlight indexing failed: \(error)")
            }
        }
    }

    static func removeMeeting(_ meetingID: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [meetingID.uuidString]
        )
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: ["com.lidia.meetings"]
        )
    }
}
