import Foundation
import SwiftData
import os

/// Parses and executes tool calls embedded in LLM voice responses.
///
/// The LLM is instructed to emit `<tool>{"action":"...", ...}</tool>` blocks
/// when the user asks it to perform an action. This executor finds those
/// blocks, runs the corresponding SwiftData mutations, and returns a
/// cleaned response (tool blocks stripped) plus execution results.
@MainActor
struct VoiceToolExecutor {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "VoiceToolExecutor")

    struct Result {
        let spokenResponse: String
        let executedActions: [String]
    }

    /// Builds a personalization prefix for system prompts.
    /// Combines settings (name, personality) with user preferences file (~/.lidia/soul.md).
    static func personalizationPrompt(settings: AppSettings) -> String {
        var parts: [String] = []
        let name = settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            parts.append("The user's name is \(name). Address them by name occasionally.")
        }
        parts.append(settings.assistantPersonality.promptFragment)

        // Integration status — so the assistant can guide the user
        let integrations = integrationStatus(settings: settings)
        if !integrations.isEmpty {
            parts.append("\nIntegration status (if the user asks you to do something requiring an unconfigured integration, tell them to set it up in Settings):\n\(integrations)")
        }

        // Load SOUL.md — user-edited personality and instructions
        let soulContent = loadFile(soulFilePath, maxChars: 2000)
        if !soulContent.isEmpty {
            parts.append("\nSOUL.md (the user's personality and instructions for you — follow these closely):\n\(soulContent)")
        }

        // Load MEMORY.md — things you've remembered about the user
        let memoryContent = loadFile(memoryFilePath, maxChars: 2000)
        if !memoryContent.isEmpty {
            parts.append("\nMEMORY.md (things you've learned about this user — reference naturally):\n\(memoryContent)")
        }

        return parts.joined(separator: " ")
    }

    /// Base directory for LidIA config files.
    static let lidiaDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.lidia"
    }()

    /// Path to the SOUL.md file — user-edited personality and instructions.
    static let soulFilePath: String = { "\(lidiaDir)/SOUL.md" }()

    /// Path to the MEMORY.md file — assistant-written long-term memory.
    static let memoryFilePath: String = { "\(lidiaDir)/MEMORY.md" }()

    /// Returns a summary of which integrations are configured.
    private static func integrationStatus(settings: AppSettings) -> String {
        var lines: [String] = []
        lines.append("- Notion: \(!settings.notionAPIKey.isEmpty ? "configured" : "not configured")")
        lines.append("- Google Calendar: \(settings.googleCalendarEnabled && !settings.googleClientID.isEmpty ? "configured" : "not configured")")
        lines.append("- Apple Calendar: \(settings.calendarEnabled ? "enabled" : "not enabled")")
        lines.append("- Apple Reminders: \(settings.remindersEnabled ? "enabled" : "not enabled")")
        lines.append("- n8n Webhooks: \(settings.n8nEnabled && !settings.n8nWebhookURL.isEmpty ? "configured" : "not configured")")
        lines.append("- OpenAI API: \(!settings.openaiAPIKey.isEmpty ? "configured" : "not configured")")
        lines.append("- Anthropic API: \(!settings.anthropicAPIKey.isEmpty ? "configured" : "not configured")")
        return lines.joined(separator: "\n")
    }

    /// Reads a file if it exists, capped at maxChars.
    private static func loadFile(_ path: String, maxChars: Int) -> String {
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }
        return String(content.prefix(maxChars))
    }

    /// Tool definitions appended to the voice system prompt.
    static let toolPrompt = """
        You can perform actions by including tool calls in your response. \
        Wrap each in <tool>...</tool> tags with JSON inside. \
        You may include multiple tool calls. Add a brief confirmation (1 sentence max) — \
        the tool blocks are hidden from the user.

        Available tools:

        1. Mark an action item complete:
           <tool>{"action":"complete_action_item","title":"partial title match"}</tool>

        2. Mark an action item incomplete:
           <tool>{"action":"uncomplete_action_item","title":"partial title match"}</tool>

        3. Change an action item's deadline:
           <tool>{"action":"set_deadline","title":"partial title match","deadline":"2026-03-15"}</tool>
           Use ISO 8601 date format (YYYY-MM-DD). Use null to clear the deadline.

        4. Change an action item's assignee:
           <tool>{"action":"set_assignee","title":"partial title match","assignee":"person name"}</tool>
           Use null to clear the assignee.

        5. Create a new action item:
           <tool>{"action":"create_action_item","title":"the task","assignee":"person or null","deadline":"YYYY-MM-DD or null","meeting":"partial meeting title match or null"}</tool>

        6. Edit an action item's title:
           <tool>{"action":"edit_action_item","title":"partial title match","new_title":"updated title"}</tool>

        7. Delete an action item:
           <tool>{"action":"delete_action_item","title":"partial title match"}</tool>

        8. Save something to memory (facts you learn about the user):
           <tool>{"action":"save_memory","content":"User prefers meeting summaries in bullet points"}</tool>
           Use this when the user tells you a fact about themselves or a correction.
           Keep entries concise. Don't duplicate existing memories.

        9. Update your soul (personality, tone, behavioral instructions):
           <tool>{"action":"update_soul","instruction":"Always greet the user warmly"}</tool>
           Use this when the user tells you to change how you behave, your tone, language,
           or any persistent instruction about how you should act. This is YOUR personality —
           things like "be funnier", "respond in Spanish", "don't use emojis".

        10. Get a summary of a recent or specific meeting:
            <tool>{"action":"get_meeting_summary","meeting":"partial title match or null for most recent"}</tool>

        11. List upcoming meetings:
            <tool>{"action":"get_next_meetings","count":3}</tool>

        12. Search past meetings:
            <tool>{"action":"search_meetings","query":"search term"}</tool>

        13. Prepare for an upcoming meeting (attendee history, past action items, talking points):
            <tool>{"action":"prepare_meeting","meeting":"partial title match"}</tool>

        14. Run a recipe on a meeting:
            <tool>{"action":"run_recipe","recipe":"Coach Me","meeting":"partial title match or null for most recent"}</tool>
            Available recipes: Coach Me, Write a Brief, Follow-up Email, Extract Decisions, Executive Summary, Action Plan

        15. Look up a person and their meeting history:
            <tool>{"action":"lookup_person","name":"person name"}</tool>
            Use this when the user asks about a specific person — what they discussed, past meetings, open action items with them.

        When matching by title, use a substring that uniquely identifies the item. \
        If the user's request is ambiguous, ask for clarification instead of guessing.

        Si el usuario habla en español, responde en español. Usa las mismas herramientas — \
        los nombres de las acciones son siempre en inglés pero tu respuesta al usuario debe ser en su idioma.
        """

    // MARK: - Parse + Execute

    static func process(
        response: String,
        modelContext: ModelContext
    ) -> Result {
        let (cleaned, toolCalls) = extractToolCalls(from: response)
        guard !toolCalls.isEmpty else {
            return Result(spokenResponse: response, executedActions: [])
        }

        let context = modelContext
        var executed: [String] = []

        for call in toolCalls {
            let result = execute(call, in: context)
            executed.append(result)
        }

        do {
            try context.save()
        } catch {
            logger.error("Failed to save after voice tool execution: \(error)")
        }

        return Result(
            spokenResponse: cleaned.trimmingCharacters(in: .whitespacesAndNewlines),
            executedActions: executed
        )
    }

    // MARK: - Tool Marker Stripping

    /// Strips `<tool>...</tool>` blocks from text, returning only the spoken content.
    /// Used by sentence-level TTS to avoid synthesizing tool call JSON.
    nonisolated static func stripToolMarkers(_ text: String) -> String {
        let pattern = #"<tool>\s*\{.*?\}\s*</tool>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tool Call Extraction

    private static func extractToolCalls(from text: String) -> (cleaned: String, calls: [[String: Any]]) {
        var cleaned = text
        var calls: [[String: Any]] = []

        let pattern = #"<tool>\s*(\{.*?\})\s*</tool>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return (text, [])
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let jsonRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range, in: text) else { continue }

            let jsonString = String(text[jsonRange])
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                calls.insert(json, at: 0)
            }
            cleaned.removeSubrange(fullRange)
        }

        return (cleaned, calls)
    }

    // MARK: - Execution

    private static func execute(_ call: [String: Any], in context: ModelContext) -> String {
        guard let action = call["action"] as? String else {
            return "Unknown tool call (no action)"
        }

        switch action {
        case "complete_action_item":
            return setCompletion(call, completed: true, in: context)
        case "uncomplete_action_item":
            return setCompletion(call, completed: false, in: context)
        case "set_deadline":
            return setDeadline(call, in: context)
        case "set_assignee":
            return setAssignee(call, in: context)
        case "create_action_item":
            return createActionItem(call, in: context)
        case "edit_action_item":
            return editActionItem(call, in: context)
        case "delete_action_item":
            return deleteActionItem(call, in: context)
        case "save_memory":
            return saveMemory(call)
        case "update_soul":
            return updateSoul(call)
        case "get_meeting_summary":
            return getMeetingSummary(call, in: context)
        case "get_next_meetings":
            return getNextMeetings(call, in: context)
        case "search_meetings":
            return searchMeetings(call, in: context)
        case "prepare_meeting":
            return prepareMeeting(call, in: context)
        case "run_recipe":
            return runRecipe(call, in: context)
        case "lookup_person":
            return lookupPerson(call, in: context)
        default:
            logger.warning("Unknown voice tool action: \(action)")
            return "Unknown action: \(action)"
        }
    }

    // MARK: - Individual Actions

    private static func setCompletion(_ call: [String: Any], completed: Bool, in context: ModelContext) -> String {
        guard let titleMatch = call["title"] as? String else { return "Missing title" }
        guard let item = findActionItem(titleMatch, in: context) else {
            return "No action item matching '\(titleMatch)'"
        }
        item.isCompleted = completed
        let verb = completed ? "completed" : "reopened"
        logger.info("Voice tool: \(verb) action item '\(item.title)'")
        return "\(verb): \(item.title)"
    }

    private static func setDeadline(_ call: [String: Any], in context: ModelContext) -> String {
        guard let titleMatch = call["title"] as? String else { return "Missing title" }
        guard let item = findActionItem(titleMatch, in: context) else {
            return "No action item matching '\(titleMatch)'"
        }

        if let deadlineStr = call["deadline"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: deadlineStr) {
                item.setPreciseDeadline(date)
                logger.info("Voice tool: set deadline for '\(item.title)' to \(deadlineStr)")
                return "Updated deadline: \(item.title) → \(deadlineStr)"
            } else {
                item.deadline = deadlineStr
                logger.info("Voice tool: set text deadline for '\(item.title)' to \(deadlineStr)")
                return "Updated deadline: \(item.title) → \(deadlineStr)"
            }
        } else {
            item.setPreciseDeadline(nil)
            logger.info("Voice tool: cleared deadline for '\(item.title)'")
            return "Cleared deadline: \(item.title)"
        }
    }

    private static func setAssignee(_ call: [String: Any], in context: ModelContext) -> String {
        guard let titleMatch = call["title"] as? String else { return "Missing title" }
        guard let item = findActionItem(titleMatch, in: context) else {
            return "No action item matching '\(titleMatch)'"
        }

        let assignee = call["assignee"] as? String
        item.assignee = assignee
        let desc = assignee ?? "nobody"
        logger.info("Voice tool: set assignee for '\(item.title)' to \(desc)")
        return "Updated assignee: \(item.title) → \(desc)"
    }

    private static func createActionItem(_ call: [String: Any], in context: ModelContext) -> String {
        guard let title = call["title"] as? String, !title.isEmpty else { return "Missing title" }

        let assignee = call["assignee"] as? String
        var deadlineDate: Date?
        var deadlineStr: String?
        if let ds = call["deadline"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            deadlineDate = formatter.date(from: ds)
            deadlineStr = ds
        }

        let item = ActionItem(
            title: title,
            assignee: assignee,
            deadline: deadlineStr,
            deadlineDate: deadlineDate
        )

        // Attach to a meeting if specified
        if let meetingMatch = call["meeting"] as? String {
            if let meeting = findMeeting(meetingMatch, in: context) {
                item.meeting = meeting
                meeting.actionItems.append(item)
            }
        }

        context.insert(item)
        logger.info("Voice tool: created action item '\(title)'")
        return "Created: \(title)"
    }

    private static func editActionItem(_ call: [String: Any], in context: ModelContext) -> String {
        guard let titleMatch = call["title"] as? String else { return "Missing title" }
        guard let newTitle = call["new_title"] as? String, !newTitle.isEmpty else { return "Missing new_title" }
        guard let item = findActionItem(titleMatch, in: context) else {
            return "No action item matching '\(titleMatch)'"
        }
        let old = item.title
        item.title = newTitle
        logger.info("Voice tool: renamed '\(old)' → '\(newTitle)'")
        return "Renamed: \(old) → \(newTitle)"
    }

    private static func deleteActionItem(_ call: [String: Any], in context: ModelContext) -> String {
        guard let titleMatch = call["title"] as? String else { return "Missing title" }
        guard let item = findActionItem(titleMatch, in: context) else {
            return "No action item matching '\(titleMatch)'"
        }
        let title = item.title
        context.delete(item)
        logger.info("Voice tool: deleted action item '\(title)'")
        return "Deleted: \(title)"
    }

    private static func saveMemory(_ call: [String: Any]) -> String {
        guard let content = call["content"] as? String, !content.isEmpty else {
            return "Missing memory content"
        }

        let dir = URL(fileURLWithPath: lidiaDir)
        let path = memoryFilePath

        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Append to MEMORY.md (create if needed)
        let entry = "- \(content)\n"
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                handle.closeFile()
            }
        } else {
            let header = "# LidIA Memory\n\nThings I've learned about you:\n\n\(entry)"
            try? header.write(toFile: path, atomically: true, encoding: .utf8)
        }

        logger.info("Voice tool: saved memory — \(content)")
        return "Remembered: \(content)"
    }

    private static func updateSoul(_ call: [String: Any]) -> String {
        guard let instruction = call["instruction"] as? String, !instruction.isEmpty else {
            return "Missing soul instruction"
        }

        let dir = URL(fileURLWithPath: lidiaDir)
        let path = soulFilePath

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let entry = "- \(instruction)\n"
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                handle.closeFile()
            }
        } else {
            let header = "# LidIA Soul\n\n\(entry)"
            try? header.write(toFile: path, atomically: true, encoding: .utf8)
        }

        logger.info("Voice tool: updated soul — \(instruction)")
        return "Soul updated: \(instruction)"
    }

    // MARK: - Meeting Query Tools

    private static func getMeetingSummary(_ call: [String: Any], in context: ModelContext) -> String {
        let meeting: Meeting?
        if let titleMatch = call["meeting"] as? String {
            meeting = findMeeting(titleMatch, in: context)
        } else {
            // Most recent completed meeting
            meeting = fetchMostRecentMeeting(in: context)
        }
        guard let meeting else { return "No matching meeting found." }
        let summary = (meeting.userEditedSummary ?? meeting.summary)
        let preview = summary.isEmpty ? "(no summary available)" : String(summary.prefix(500))
        let dateStr = meeting.date.formatted(date: .abbreviated, time: .shortened)
        return "Meeting: \(meeting.title) (\(dateStr))\n\(preview)"
    }

    private static func getNextMeetings(_ call: [String: Any], in context: ModelContext) -> String {
        let count = (call["count"] as? Int) ?? 3
        do {
            let now = Date.now
            let descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate { $0.date > now },
                sortBy: [SortDescriptor(\Meeting.date, order: .forward)]
            )
            var meetings = try context.fetch(descriptor)
            meetings = Array(meetings.prefix(count))
            if meetings.isEmpty { return "No upcoming meetings found." }
            return meetings.map { m in
                let dateStr = m.date.formatted(date: .abbreviated, time: .shortened)
                let attendees = m.calendarAttendees?.joined(separator: ", ") ?? "no attendees"
                return "- \(m.title) — \(dateStr) (\(attendees))"
            }.joined(separator: "\n")
        } catch {
            logger.error("Failed to fetch upcoming meetings: \(error)")
            return "Error fetching upcoming meetings."
        }
    }

    private static func searchMeetings(_ call: [String: Any], in context: ModelContext) -> String {
        guard let query = call["query"] as? String, !query.isEmpty else {
            return "Missing search query."
        }
        let queryLower = query.lowercased()
        do {
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\Meeting.date, order: .reverse)]
            )
            let all = try context.fetch(descriptor)
            let matches = all.filter { m in
                m.title.lowercased().contains(queryLower) ||
                (m.userEditedSummary ?? m.summary).lowercased().contains(queryLower)
            }
            let top = Array(matches.prefix(3))
            if top.isEmpty { return "No meetings matching '\(query)'." }
            return top.map { m in
                let dateStr = m.date.formatted(date: .abbreviated, time: .shortened)
                let summary = (m.userEditedSummary ?? m.summary)
                let preview = summary.isEmpty ? "(no summary)" : String(summary.prefix(150))
                return "- \(m.title) (\(dateStr)): \(preview)"
            }.joined(separator: "\n\n")
        } catch {
            logger.error("Failed to search meetings: \(error)")
            return "Error searching meetings."
        }
    }

    private static func prepareMeeting(_ call: [String: Any], in context: ModelContext) -> String {
        guard let titleMatch = call["meeting"] as? String else { return "Missing meeting title." }
        guard let meeting = findMeeting(titleMatch, in: context) else {
            return "No meeting matching '\(titleMatch)'."
        }

        var parts: [String] = []
        let dateStr = meeting.date.formatted(date: .abbreviated, time: .shortened)
        parts.append("Preparing for: \(meeting.title) — \(dateStr)")

        let attendees = meeting.calendarAttendees ?? []
        if !attendees.isEmpty {
            parts.append("Attendees: \(attendees.joined(separator: ", "))")
        }

        // Find past meetings with overlapping attendees
        if !attendees.isEmpty {
            let attendeesLower = Set(attendees.map { $0.lowercased() })
            do {
                let descriptor = FetchDescriptor<Meeting>(
                    sortBy: [SortDescriptor(\Meeting.date, order: .reverse)]
                )
                let all = try context.fetch(descriptor)
                let pastWithSameAttendees = all.filter { m in
                    guard m.id != meeting.id, m.date < Date.now else { return false }
                    let mAttendees = Set((m.calendarAttendees ?? []).map { $0.lowercased() })
                    return !mAttendees.isDisjoint(with: attendeesLower)
                }
                let recentPast = Array(pastWithSameAttendees.prefix(3))
                if !recentPast.isEmpty {
                    parts.append("\nPast meetings with these attendees:")
                    for m in recentPast {
                        let d = m.date.formatted(date: .abbreviated, time: .omitted)
                        parts.append("- \(m.title) (\(d))")
                    }
                }

                // Open action items for those attendees
                let actionDescriptor = FetchDescriptor<ActionItem>(
                    predicate: #Predicate { !$0.isCompleted }
                )
                let openItems = try context.fetch(actionDescriptor)
                let relevantItems = openItems.filter { item in
                    guard let assignee = item.assignee else { return false }
                    return attendeesLower.contains(assignee.lowercased())
                }
                if !relevantItems.isEmpty {
                    parts.append("\nOpen action items for attendees:")
                    for item in relevantItems.prefix(5) {
                        let assignee = item.assignee ?? "unassigned"
                        parts.append("- [\(assignee)] \(item.title)")
                    }
                }
            } catch {
                logger.error("Failed to prepare meeting: \(error)")
            }
        }

        return parts.joined(separator: "\n")
    }

    private static func runRecipe(_ call: [String: Any], in context: ModelContext) -> String {
        guard let recipeName = call["recipe"] as? String, !recipeName.isEmpty else {
            return "Missing recipe name."
        }
        let validRecipes = ["Coach Me", "Write a Brief", "Follow-up Email",
                            "Extract Decisions", "Executive Summary", "Action Plan"]
        let matched = validRecipes.first { $0.lowercased() == recipeName.lowercased() }
        guard let recipe = matched else {
            return "Unknown recipe '\(recipeName)'. Available: \(validRecipes.joined(separator: ", "))"
        }

        let meeting: Meeting?
        if let titleMatch = call["meeting"] as? String {
            meeting = findMeeting(titleMatch, in: context)
        } else {
            meeting = fetchMostRecentMeeting(in: context)
        }
        guard let meeting else { return "No matching meeting found." }

        logger.info("Voice tool: recipe '\(recipe)' queued for '\(meeting.title)'")
        return "Recipe '\(recipe)' queued for \(meeting.title). It will run in the meeting detail view."
    }

    private static func lookupPerson(_ call: [String: Any], in context: ModelContext) -> String {
        guard let name = call["name"] as? String, !name.isEmpty else {
            return "Missing person name."
        }
        let nameLower = name.lowercased()
        do {
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\Meeting.date, order: .reverse)]
            )
            let allMeetings = try context.fetch(descriptor)

            // Find meetings where any attendee matches the name (case-insensitive partial match)
            let matchingMeetings = allMeetings.filter { meeting in
                guard let attendees = meeting.calendarAttendees else { return false }
                return attendees.contains { attendee in
                    let parsed = RelationshipStore.parseAttendee(attendee)
                    let displayName = parsed.displayName ?? ""
                    let email = parsed.email ?? ""
                    let emailName = RelationshipStore.displayNameFromEmail(email)
                    return displayName.lowercased().contains(nameLower)
                        || emailName.lowercased().contains(nameLower)
                        || email.lowercased().contains(nameLower)
                }
            }

            guard !matchingMeetings.isEmpty else {
                return "No meetings found with '\(name)'."
            }

            var parts: [String] = ["Found \(matchingMeetings.count) meeting\(matchingMeetings.count == 1 ? "" : "s") with \(name):"]

            for meeting in matchingMeetings.prefix(5) {
                let dateStr = meeting.date.formatted(date: .abbreviated, time: .omitted)
                let totalItems = meeting.actionItems.count
                let openItems = meeting.actionItems.filter { !$0.isCompleted }.count
                var line = "- \(meeting.title) (\(dateStr))"
                if totalItems > 0 {
                    line += " — \(totalItems) action item\(totalItems == 1 ? "" : "s"), \(openItems) open"
                }
                parts.append(line)
            }

            if let lastMet = matchingMeetings.first {
                let dateStr = lastMet.date.formatted(date: .abbreviated, time: .omitted)
                parts.append("Last met: \(dateStr)")
            }

            // Gather open action items across all matching meetings
            let openItems = matchingMeetings.flatMap(\.actionItems).filter { !$0.isCompleted }
            if !openItems.isEmpty {
                parts.append("Open items with \(name):")
                for item in openItems.prefix(5) {
                    parts.append("  - \(item.title)")
                }
            }

            return parts.joined(separator: "\n")
        } catch {
            logger.error("Failed to lookup person: \(error)")
            return "Error looking up person."
        }
    }

    private static func fetchMostRecentMeeting(in context: ModelContext) -> Meeting? {
        do {
            let now = Date.now
            let descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate { $0.date <= now },
                sortBy: [SortDescriptor(\Meeting.date, order: .reverse)]
            )
            let results = try context.fetch(descriptor)
            return results.first
        } catch {
            logger.error("Failed to fetch most recent meeting: \(error)")
            return nil
        }
    }

    // MARK: - Lookup Helpers

    private static func findActionItem(_ titleSubstring: String, in context: ModelContext) -> ActionItem? {
        let query = titleSubstring.lowercased()
        do {
            let descriptor = FetchDescriptor<ActionItem>()
            let all = try context.fetch(descriptor)

            // Exact match first, then substring
            if let exact = all.first(where: { $0.title.lowercased() == query }) {
                return exact
            }
            return all.first(where: { $0.title.lowercased().contains(query) })
        } catch {
            logger.error("Failed to fetch action items: \(error)")
            return nil
        }
    }

    private static func findMeeting(_ titleSubstring: String, in context: ModelContext) -> Meeting? {
        let query = titleSubstring.lowercased()
        do {
            let descriptor = FetchDescriptor<Meeting>(
                sortBy: [SortDescriptor(\Meeting.date, order: .reverse)]
            )
            let all = try context.fetch(descriptor)
            if let exact = all.first(where: { $0.title.lowercased() == query }) {
                return exact
            }
            return all.first(where: { $0.title.lowercased().contains(query) })
        } catch {
            logger.error("Failed to fetch meetings: \(error)")
            return nil
        }
    }
}
