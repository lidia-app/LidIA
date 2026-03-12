import Foundation
import Testing
@testable import LidIA

@Test func chatMessageCodableRoundTrip() throws {
    let message = ChatBarMessage(
        role: .user,
        text: "What did I miss?",
        attachments: [FileAttachment(name: "notes.txt", content: "Agenda notes")],
        sourceMeetings: ["Weekly Sync"]
    )

    let data = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(ChatBarMessage.self, from: data)

    #expect(decoded.text == message.text)
    #expect(decoded.role == .user)
    #expect(decoded.attachments.count == 1)
    #expect(decoded.sourceMeetings == ["Weekly Sync"])
}

@Test func curatedModelListPrefersEfficientDefaults() {
    let models = [
        "gpt-4o", "gpt-4o-mini", "o3-mini", "o4-mini", "gpt-5",
    ]

    let curated = ModelMenuCatalog.curatedModels(for: .openai, availableModels: models)

    #expect(curated == ["gpt-4o-mini", "o4-mini", "o3-mini", "gpt-4o"])
}

@Test @MainActor func threadTitleUsesFirstPrompt() {
    let title = ChatBarViewModel.makeThreadTitle(from: "Summarize this week and flag blockers")
    #expect(title == "Summarize this week and flag blockers")
}
