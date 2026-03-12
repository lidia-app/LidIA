import Testing
import SwiftData
@testable import LidIA

@Test func buildRawTextFromTranscriptWords() {
    let words = [
        TranscriptWord(word: "lets", start: 0, end: 0.3, confidence: 0.9, speaker: 0),
        TranscriptWord(word: "ship", start: 0.3, end: 0.6, confidence: 0.9, speaker: 0),
        TranscriptWord(word: "it", start: 0.6, end: 0.8, confidence: 0.9, speaker: 0),
    ]
    let rawText = MeetingPipeline.buildRawText(from: words)
    #expect(rawText == "lets ship it")
}

@Test func buildRawTextHandlesEmptyArray() {
    let rawText = MeetingPipeline.buildRawText(from: [])
    #expect(rawText == "")
}

@Test func buildRawTextHandlesSingleWord() {
    let words = [
        TranscriptWord(word: "hello", start: 0, end: 0.5, confidence: 0.95, speaker: 1),
    ]
    let rawText = MeetingPipeline.buildRawText(from: words)
    #expect(rawText == "hello")
}
