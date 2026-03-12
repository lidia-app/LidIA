import Testing
import SwiftData
@testable import LidIA

@Test func retrievalPrefersAttendeeOverlap() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Meeting.self, ActionItem.self, configurations: config)
    let context = ModelContext(container)

    let a = Meeting(title: "Sprint Planning", date: .now, summary: "Roadmap discussion", status: .complete)
    a.calendarAttendees = ["Alex Rivera"]

    let b = Meeting(title: "Infra Review", date: .now.addingTimeInterval(-86_400), summary: "Latency work", status: .complete)
    b.calendarAttendees = ["Jordan Kim"]

    context.insert(a)
    context.insert(b)
    try context.save()

    let meetings = try context.fetch(FetchDescriptor<Meeting>())
    let ranked = MeetingContextRetrievalService.relevantMeetings(for: "What did I discuss with Alex?", from: meetings, limit: 2)

    #expect(ranked.first?.title == "Sprint Planning")
}

@Test func effectiveSummaryUsesUserEdit() {
    let meeting = Meeting(title: "Sync", summary: "Generated summary", status: .complete)
    meeting.userEditedSummary = "Edited summary"

    #expect(MeetingContextRetrievalService.effectiveSummary(for: meeting) == "Edited summary")
}

@Test func retryClassifierTreats429AsRetryable() {
    #expect(RetryClassifier.isRetryableHTTP(statusCode: 429))
    #expect(!RetryClassifier.isRetryableHTTP(statusCode: 400))
}
