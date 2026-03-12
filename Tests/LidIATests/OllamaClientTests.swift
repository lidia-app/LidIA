import Testing
import Foundation
@testable import LidIA

@Test func llmChatMessageCoding() throws {
    let message = LLMChatMessage(role: "user", content: "Hello")
    let data = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(LLMChatMessage.self, from: data)
    #expect(decoded.role == "user")
    #expect(decoded.content == "Hello")
}

@Test func meetingSummaryResponseParsing() throws {
    let json = """
    {
        "title": "Sprint Planning",
        "summary": "Discussed Q2 priorities.",
        "decisions": ["Focus on mobile first"],
        "actionItems": [
            {"title": "Write RFC", "assignee": "Juan", "deadline": "by Friday"}
        ]
    }
    """.data(using: .utf8)!

    let result = try JSONDecoder().decode(MeetingSummaryResponse.self, from: json)
    #expect(result.title == "Sprint Planning")
    #expect(result.actionItems.count == 1)
    #expect(result.actionItems[0].assignee == "Juan")
}
