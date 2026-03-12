import Testing
import Foundation
@testable import LidIA

@Test func notionBlocksFromMarkdown() async throws {
    let markdown = """
    ## Summary
    We discussed the roadmap.

    ## Action Items
    - Write RFC
    - Deploy staging
    """
    let blocks = NotionClient.markdownToBlocks(markdown)
    #expect(blocks.count == 5) // heading + paragraph + heading + 2 bullets
    #expect(blocks[0]["type"] as? String == "heading_2")
    #expect(blocks[3]["type"] as? String == "bulleted_list_item")
}

@Test func notionPagePayload() async throws {
    let payload = NotionClient.createPagePayload(
        databaseID: "db-123",
        title: "Sprint Planning",
        date: Date(timeIntervalSince1970: 1709510400),
        duration: 1800,
        bodyMarkdown: "## Summary\nGood meeting."
    )
    let json = payload as [String: Any]
    #expect(json["parent"] != nil)
}

@Test func notionTaskPayloadUsesSchemaProperties() async throws {
    let schema = NotionClient.TaskDatabaseSchema(
        titlePropertyName: "Task",
        datePropertyName: "Due",
        checkboxPropertyName: "Completed",
        richTextPropertyName: "Meeting"
    )
    let deadline = Date(timeIntervalSince1970: 1_709_510_400)

    let payload = NotionClient.createTaskPagePayload(
        databaseID: "tasks-db",
        schema: schema,
        title: "Write RFC",
        deadline: deadline,
        isCompleted: true,
        meetingTitle: "Sprint Planning"
    )

    let properties = try #require(payload["properties"] as? [String: Any])
    let titleProperty = try #require(properties["Task"] as? [String: Any])
    let dateProperty = try #require(properties["Due"] as? [String: Any])
    let checkboxProperty = try #require(properties["Completed"] as? [String: Any])
    let richTextProperty = try #require(properties["Meeting"] as? [String: Any])

    #expect((titleProperty["title"] as? [[String: Any]])?.isEmpty == false)
    #expect(dateProperty["date"] != nil)
    #expect(checkboxProperty["checkbox"] as? Bool == true)
    #expect((richTextProperty["rich_text"] as? [[String: Any]])?.isEmpty == false)
}
