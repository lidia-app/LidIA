import Foundation

struct TranscriptWord: Codable, Sendable, Equatable {
    var word: String
    var start: TimeInterval
    var end: TimeInterval
    var confidence: Double
    var speaker: Int?
    var speakerName: String?
    var isLocalSpeaker: Bool?
}
