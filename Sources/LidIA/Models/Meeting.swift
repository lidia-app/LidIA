import Foundation
import SwiftData

enum MeetingStatus: String, Codable, Sendable {
    case recording
    case processing
    case queued
    case complete
    case failed
}

@Model
final class Meeting {
    var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    @Attribute(.externalStorage) var rawTranscript: [TranscriptWord]
    @Attribute(.externalStorage) var refinedTranscript: String
    @Attribute(.externalStorage) var summary: String
    var status: MeetingStatus
    var processingRetryCount: Int
    var audioFilePath: String?
    @Attribute(.externalStorage) var userEditedTranscript: String?
    @Attribute(.externalStorage) var userEditedSummary: String?
    var notionPageID: String?
    var calendarEventID: String?
    var calendarAttendees: [String]?
    var templateID: UUID?
    var templateAutoDetected: Bool
    var processingError: String?
    var notes: String
    var folder: String?
    /// JSON-encoded structured summary with quote anchors for transcript linking.
    var structuredSummary: Data?
    @Relationship(deleteRule: .cascade, inverse: \ActionItem.meeting) var actionItems: [ActionItem]

    init(
        title: String = "",
        date: Date = .now,
        duration: TimeInterval = 0,
        rawTranscript: [TranscriptWord] = [],
        refinedTranscript: String = "",
        summary: String = "",
        status: MeetingStatus = .recording,
        processingRetryCount: Int = 0,
        audioFilePath: String? = nil,
        userEditedTranscript: String? = nil,
        userEditedSummary: String? = nil,
        notionPageID: String? = nil,
        calendarEventID: String? = nil,
        calendarAttendees: [String]? = nil,
        templateID: UUID? = nil,
        templateAutoDetected: Bool = true,
        processingError: String? = nil,
        notes: String = "",
        folder: String? = nil,
        actionItems: [ActionItem] = []
    ) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.duration = duration
        self.rawTranscript = rawTranscript
        self.refinedTranscript = refinedTranscript
        self.summary = summary
        self.status = status
        self.processingRetryCount = processingRetryCount
        self.audioFilePath = audioFilePath
        self.userEditedTranscript = userEditedTranscript
        self.userEditedSummary = userEditedSummary
        self.notionPageID = notionPageID
        self.calendarEventID = calendarEventID
        self.calendarAttendees = calendarAttendees
        self.templateID = templateID
        self.templateAutoDetected = templateAutoDetected
        self.processingError = processingError
        self.notes = notes
        self.folder = folder
        self.actionItems = actionItems
    }

    /// Stable hash for attendee set, used for template recurrence matching.
    var attendeeHash: String? {
        guard let attendees = calendarAttendees, !attendees.isEmpty else { return nil }
        return attendees.sorted().joined(separator: "|").lowercased()
    }

    #Index<Meeting>([\.date], [\.calendarEventID])
}
