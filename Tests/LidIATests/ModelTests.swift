import Foundation
import Testing
import SwiftData
@testable import LidIA

@Test func meetingCreation() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Meeting.self, ActionItem.self,
        configurations: config
    )
    let context = ModelContext(container)

    let meeting = Meeting(title: "Standup", date: .now)
    context.insert(meeting)
    try context.save()

    let meetings = try context.fetch(FetchDescriptor<Meeting>())
    #expect(meetings.count == 1)
    #expect(meetings.first?.title == "Standup")
    #expect(meetings.first?.status == .recording)
}

@Test func actionItemRelationship() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Meeting.self, ActionItem.self,
        configurations: config
    )
    let context = ModelContext(container)

    let meeting = Meeting(title: "Planning", date: .now)
    let item = ActionItem(title: "Write RFC")
    item.meeting = meeting
    meeting.actionItems.append(item)
    context.insert(meeting)
    try context.save()

    let meetings = try context.fetch(FetchDescriptor<Meeting>())
    #expect(meetings.first?.actionItems.count == 1)
    #expect(meetings.first?.actionItems.first?.title == "Write RFC")
}

@Test func actionItemPreciseDeadlineLifecycle() async throws {
    let item = ActionItem(title: "Write RFC")
    let deadline = Date(timeIntervalSince1970: 1_709_510_400)

    item.setPreciseDeadline(deadline)

    #expect(item.deadlineDate == deadline)
    #expect(item.deadline == ActionItem.formattedDeadline(from: deadline))
    #expect(item.displayDeadline == ActionItem.formattedDeadline(from: deadline))

    item.setPreciseDeadline(nil)

    #expect(item.deadlineDate == nil)
    #expect(item.deadline == nil)
    #expect(item.displayDeadline == nil)
}

@Test func transcriptWordCoding() async throws {
    let word = TranscriptWord(word: "hello", start: 1.0, end: 1.5, confidence: 0.95, speaker: 0)
    let data = try JSONEncoder().encode(word)
    let decoded = try JSONDecoder().decode(TranscriptWord.self, from: data)
    #expect(decoded.word == "hello")
    #expect(decoded.confidence == 0.95)
}

@Test func audioChunkSource() {
    let mic = AudioChunk(samples: [0.1, 0.2], sampleRate: 16000, timestamp: 0, source: .mic)
    let system = AudioChunk(samples: [0.1, 0.2], sampleRate: 16000, timestamp: 0, source: .system)
    let unknown = AudioChunk(samples: [0.1, 0.2], sampleRate: 16000, timestamp: 0)
    #expect(mic.source == .mic)
    #expect(system.source == .system)
    #expect(unknown.source == .unknown)
}
