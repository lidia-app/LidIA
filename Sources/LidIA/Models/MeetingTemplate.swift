import Foundation

enum OutputFormat: String, Codable, Sendable, CaseIterable {
    case bullets
    case prose
    case table
}

struct SectionSpec: Codable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var description: String
    var format: OutputFormat

    init(name: String, description: String = "", format: OutputFormat = .bullets) {
        self.name = name
        self.description = description
        self.format = format
    }
}

struct AutoDetectRules: Codable, Sendable {
    var attendeeCount: ClosedRange<Int>?
    var titleKeywords: [String]

    init(attendeeCount: ClosedRange<Int>? = nil, titleKeywords: [String] = []) {
        self.attendeeCount = attendeeCount
        self.titleKeywords = titleKeywords
    }

    func matches(title: String, attendees: Int) -> Bool {
        if let range = attendeeCount, !range.contains(attendees) {
            return false
        }
        if !titleKeywords.isEmpty {
            let lower = title.lowercased()
            return titleKeywords.contains { lower.contains($0.lowercased()) }
        }
        return attendeeCount != nil
    }
}

struct MeetingTemplate: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var emoji: String
    var description: String
    var systemPrompt: String
    var sections: [SectionSpec]
    var isAdvancedMode: Bool
    var autoDetectRules: AutoDetectRules
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "",
        description: String = "",
        systemPrompt: String,
        sections: [SectionSpec] = [],
        isAdvancedMode: Bool = true,
        autoDetectRules: AutoDetectRules = AutoDetectRules(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
        self.systemPrompt = systemPrompt
        self.sections = sections
        self.isAdvancedMode = isAdvancedMode
        self.autoDetectRules = autoDetectRules
        self.isBuiltIn = isBuiltIn
    }

    /// Build system prompt from structured sections when not in advanced mode.
    var effectiveSystemPrompt: String {
        guard !isAdvancedMode, !sections.isEmpty else { return systemPrompt }
        var prompt = """
        You are a professional meeting analyst. Given a meeting transcript, produce a JSON response with:
        - "title": a descriptive meeting title (max 10 words)
        - "summary": detailed markdown structured with ### headings for each section below. \
        Under each heading, write thorough bullet points with specific facts, names, numbers, \
        dates, and context from the transcript. Use nested sub-bullets for supporting details:
        """
        for section in sections {
            let formatHint: String
            switch section.format {
            case .bullets: formatHint = "as bullet points"
            case .prose: formatHint = "as a paragraph"
            case .table: formatHint = "as a markdown table"
            }
            if section.description.isEmpty {
                prompt += "\n  **\(section.name)** — \(formatHint)"
            } else {
                prompt += "\n  **\(section.name)** — \(section.description) (\(formatHint))"
            }
        }
        prompt += """
        \n- "summary_sections": array of section objects matching the sections above. Each has "heading" and "bullets" array. \
        Each bullet has "text" and "source_quote" (a SHORT verbatim quote of 5-15 words from the transcript, or null).
        - "decisions": array of strings — decisions made (empty array if none)
        - "actionItems": array of {"title", "assignee" (or null), "deadline" (or null), "source_quote" (or null)} — only items EXPLICITLY committed to

        CRITICAL: "summary" MUST be a single JSON string (not an array). Use \\n for newlines.
        ABSOLUTE RULE — NEVER FABRICATE: Only include information EXPLICITLY stated in the transcript. \
        Do NOT invent names, dates, numbers, or any details not present. If the transcript is brief, keep the summary brief.

        For "summary_sections": create an array of section objects. Each section has a "heading" (string) and "bullets" array. \
        Each bullet has "text" (the bullet content) and "source_quote" (a SHORT verbatim quote of 5-15 words \
        copied exactly from the transcript that supports this bullet point, or null if no specific quote applies). \
        The quotes must appear VERBATIM in the transcript — do not paraphrase or fabricate quotes.

        For each action item, include a "source_quote": the verbatim words where the commitment was made (or null).

        IMPORTANT: Also include a flat "summary" field with the same content as markdown (### headings + - bullets) \
        for backward compatibility. Both "summary" and "summary_sections" must be present.

        Respond ONLY with valid JSON. No markdown fences. No commentary.
        """
        return prompt
    }

    static let general = MeetingTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "General",
        emoji: "📝",
        description: "Default template for any meeting type",
        systemPrompt: """
        You are a professional meeting analyst who produces rich, detailed meeting notes. \
        Given a meeting transcript, produce a JSON object with exactly this structure:

        {"title": "...", "summary": "...", "summary_sections": [{"heading": "...", "bullets": [{"text": "...", "source_quote": "..."}]}], "decisions": [...], "actionItems": [{"title": "...", "assignee": "...", "deadline": "...", "source_quote": "..."}]}

        CRITICAL: "summary" MUST be a single JSON string (not an array). Use \\n for newlines inside the string.

        ABSOLUTE RULE — NEVER FABRICATE: Only include information that is EXPLICITLY stated in the transcript. \
        Do NOT invent names, dates, numbers, percentages, deadlines, tools, or any details not present in the transcript. \
        If the transcript is vague, your summary must be equally vague. If no specific deadline was mentioned, \
        do NOT create one. If no specific person was assigned a task, set assignee to null. \
        It is far better to produce a short, accurate summary than a detailed, fabricated one.

        SPEAKER ATTRIBUTION: When the transcript contains speaker labels (e.g., **Name:**), \
        ALWAYS attribute statements to the speaker by name in the summary. Write "**Sarah** proposed X" \
        not "It was proposed that X." Write "**Mark** raised concerns about Y" not "Concerns were raised." \
        Every bullet point should name WHO said or did the thing whenever the transcript identifies the speaker.

        For the "summary" string, write detailed markdown with multiple ### sections. \
        Identify 3-6 natural topics from the meeting and create a ### heading for each. \
        Under each heading, write detailed bullet points that capture:
        - Specific facts, numbers, names, dates, and timelines ACTUALLY mentioned
        - WHO said or proposed each point (use bold **Name** when speaker is identified)
        - Context and reasoning behind statements (not just conclusions)
        - Nested sub-bullets (using 2-space indent) for supporting details
        - Technical specifics when discussed (tools, processes, architectures)
        Do NOT write a generic overview. Extract the SUBSTANCE of what was discussed. \
        Every bullet should contain specific information from the transcript, not vague summaries. \
        If someone mentioned a timeline, include the exact dates. If someone named a tool, include it. \
        If a number was discussed, include it. If something was NOT discussed, do NOT include it.

        For "decisions": array of strings — specific decisions ACTUALLY made (include who decided and context). Empty array if none.

        ACTION ITEMS vs SUGGESTIONS — this distinction is critical:
        - An action item is a COMMITMENT: someone said "I will...", "I'll...", "Let me...", "I'll take care of..." \
        with a clear owner who volunteered or was assigned the task.
        - A suggestion is NOT an action item: "we should...", "it would be good to...", "maybe we could...", \
        "we need to think about..." — these are discussion points, not commitments.
        - When in doubt, it is NOT an action item. Only include tasks where someone clearly took ownership.
        For "actionItems": array of {"title": "...", "assignee": "..." or null, "deadline": "..." or null, "source_quote": "..." or null}. \
        Only include genuine commitments where a specific person accepted responsibility. Empty array if none.

        For "summary_sections": create an array of section objects. Each section has a "heading" (string) and "bullets" array. \
        Each bullet has "text" (the bullet content) and "source_quote" (a SHORT verbatim quote of 5-15 words \
        copied exactly from the transcript that supports this bullet point, or null if no specific quote applies). \
        The quotes must appear VERBATIM in the transcript — do not paraphrase or fabricate quotes.

        For each action item, include a "source_quote": the verbatim words where the commitment was made (or null).

        IMPORTANT: Also include a flat "summary" field with the same content as markdown (### headings + - bullets) \
        for backward compatibility. Both "summary" and "summary_sections" must be present.

        Respond ONLY with valid JSON. No markdown fences. No commentary.
        """,
        isAdvancedMode: true,
        isBuiltIn: true
    )

    static let oneOnOne = MeetingTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "1:1",
        emoji: "🤝",
        description: "One-on-one meetings — priorities, feedback, next steps",
        systemPrompt: """
        You are capturing notes for a 1:1 meeting. Produce detailed, actionable notes \
        that make follow-up easy. Extract specific commitments, concerns, and context.

        Given the meeting transcript, produce a JSON object with exactly this structure:

        {"title": "...", "summary": "...", "summary_sections": [{"heading": "...", "bullets": [{"text": "...", "source_quote": "..."}]}], "decisions": [...], "actionItems": [{"title": "...", "assignee": "...", "deadline": "...", "source_quote": "..."}]}

        CRITICAL: "summary" MUST be a single JSON string (not an array). Use \\n for newlines inside the string.

        ABSOLUTE RULE — NEVER FABRICATE: Only include information that is EXPLICITLY stated in the transcript. \
        Do NOT invent names, dates, numbers, percentages, deadlines, tools, or any details not present in the transcript. \
        If the transcript is vague, your summary must be equally vague. If no specific deadline was mentioned, \
        do NOT create one. If no specific person was assigned a task, set assignee to null. \
        It is far better to produce a short, accurate summary than a detailed, fabricated one.

        SPEAKER ATTRIBUTION: When the transcript contains speaker labels (e.g., **Name:**), \
        ALWAYS attribute statements to the speaker by name. Write "**Sarah** mentioned..." \
        not "It was mentioned that..." Every bullet should name WHO said it when the speaker is identified.

        For the "summary" string, write detailed markdown with these ### sections \
        (omit any section with no relevant content):
        ### Top of Mind — most pressing issues, with context and deadlines
        ### Updates & Progress — achievements, milestones, metrics, status of previous items
        ### Challenges & Blockers — obstacles, impact, proposed solutions, dependencies
        ### Feedback & Alignment — feedback exchanged with examples, expectation alignment
        ### Next Steps & Timeline — concrete commitments with owners and deadlines

        Each section should have detailed bullets with specifics ACTUALLY from the conversation. \
        Attribute points to the speaker by name. Omit entire sections if the transcript contains nothing relevant.

        For "decisions": array of strings (empty array if none made).

        ACTION ITEMS — only genuine commitments:
        - "I will..." / "I'll..." / "Let me handle..." = action item (someone took ownership)
        - "We should..." / "It would be nice to..." / "We need to think about..." = NOT an action item
        For "actionItems": array of {"title": "...", "assignee": "..." or null, "deadline": "..." or null, "source_quote": "..." or null} — only tasks where someone accepted responsibility.

        For "summary_sections": create an array of section objects. Each section has a "heading" (string) and "bullets" array. \
        Each bullet has "text" (the bullet content) and "source_quote" (a SHORT verbatim quote of 5-15 words \
        copied exactly from the transcript that supports this bullet point, or null if no specific quote applies). \
        The quotes must appear VERBATIM in the transcript — do not paraphrase or fabricate quotes.

        For each action item, include a "source_quote": the verbatim words where the commitment was made (or null).

        IMPORTANT: Also include a flat "summary" field with the same content as markdown (### headings + - bullets) \
        for backward compatibility. Both "summary" and "summary_sections" must be present.

        Respond ONLY with valid JSON. No markdown fences. No commentary.
        """,
        isAdvancedMode: true,
        autoDetectRules: AutoDetectRules(attendeeCount: 2...2),
        isBuiltIn: true
    )

    static let brainstorm = MeetingTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Brainstorm",
        emoji: "💡",
        description: "Brainstorming sessions — ideas, themes, future directions",
        systemPrompt: """
        You are capturing notes for a brainstorming or ideation session. Focus on preserving \
        every idea discussed, the reasoning behind them, and how they connect.

        Given the meeting transcript, produce a JSON object with exactly this structure:

        {"title": "...", "summary": "...", "summary_sections": [{"heading": "...", "bullets": [{"text": "...", "source_quote": "..."}]}], "decisions": [...], "actionItems": [{"title": "...", "assignee": "...", "deadline": "...", "source_quote": "..."}]}

        CRITICAL: "summary" MUST be a single JSON string (not an array). Use \\n for newlines inside the string.

        ABSOLUTE RULE — NEVER FABRICATE: Only include information EXPLICITLY stated in the transcript. \
        Do NOT invent ideas, names, examples, or details not present. If the transcript is brief, keep the summary brief.

        SPEAKER ATTRIBUTION: When the transcript contains speaker labels (e.g., **Name:**), \
        ALWAYS attribute ideas and statements to the speaker by name. Write "**Alex** proposed..." \
        not "It was proposed that..." Credit who came up with each idea.

        For the "summary" string, write detailed markdown with these ### sections \
        (omit any section with no relevant content):
        ### Problem Context — the problem, full context, constraints, goals
        ### Ideas & Proposals — each idea with explanation, nested pros/cons, **who proposed it**
        ### Themes & Patterns — common threads, areas of agreement/disagreement
        ### Direction & Priorities — ideas that gained traction, what was parked, next steps

        Each section should have detailed bullets with specifics ACTUALLY from the conversation. \
        Always name who proposed or championed each idea.

        For "decisions": array of strings (empty array if none).

        ACTION ITEMS — only genuine commitments:
        - "I will..." / "I'll look into..." / "Let me prototype..." = action item
        - "We should explore..." / "Someone should..." / "It would be cool to..." = NOT an action item
        For "actionItems": array of {"title": "...", "assignee": "..." or null, "deadline": "..." or null, "source_quote": "..." or null} — only tasks where someone accepted responsibility.

        For "summary_sections": create an array of section objects. Each section has a "heading" (string) and "bullets" array. \
        Each bullet has "text" (the bullet content) and "source_quote" (a SHORT verbatim quote of 5-15 words \
        copied exactly from the transcript that supports this bullet point, or null if no specific quote applies). \
        The quotes must appear VERBATIM in the transcript — do not paraphrase or fabricate quotes.

        For each action item, include a "source_quote": the verbatim words where the commitment was made (or null).

        IMPORTANT: Also include a flat "summary" field with the same content as markdown (### headings + - bullets) \
        for backward compatibility. Both "summary" and "summary_sections" must be present.

        Respond ONLY with valid JSON. No markdown fences. No commentary.
        """,
        isAdvancedMode: true,
        autoDetectRules: AutoDetectRules(titleKeywords: ["brainstorm", "ideation", "ideas", "workshop"]),
        isBuiltIn: true
    )

    static let standup = MeetingTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Standup",
        emoji: "🏃",
        description: "Daily standups — status updates, blockers, plans",
        systemPrompt: """
        You are capturing notes for a team standup or status update meeting. \
        Be concise but capture every update, blocker, and commitment.

        Given the meeting transcript, produce a JSON object with exactly this structure:

        {"title": "...", "summary": "...", "summary_sections": [{"heading": "...", "bullets": [{"text": "...", "source_quote": "..."}]}], "decisions": [...], "actionItems": [{"title": "...", "assignee": "...", "deadline": "...", "source_quote": "..."}]}

        CRITICAL: "summary" MUST be a single JSON string (not an array). Use \\n for newlines inside the string.

        ABSOLUTE RULE — NEVER FABRICATE: Only include information EXPLICITLY stated in the transcript. \
        Do NOT invent names, dates, status updates, or details not present. If the transcript is brief, keep the summary brief.

        SPEAKER ATTRIBUTION: When the transcript contains speaker labels, \
        ALWAYS use the person's name. Standups are inherently per-person — every update must be attributed.

        For the "summary" string, write markdown with these ### sections (omit empty ones):
        ### Status Updates — each person's update with **name bolded**, what they completed/working on
        ### Blockers & Dependencies — **who** is blocked, what is needed, cross-team dependencies
        ### Priorities for Today/This Week — **who** committed to what, deadline-sensitive work

        For "decisions": array of strings (empty array if none).

        ACTION ITEMS — only genuine commitments:
        - "I'll finish the PR today" / "I'll review that by EOD" = action item with clear owner
        - "We need to figure out..." / "Someone should check..." = NOT an action item
        For "actionItems": array of {"title": "...", "assignee": "..." or null, "deadline": "..." or null, "source_quote": "..." or null} — only tasks where someone accepted responsibility.

        For "summary_sections": create an array of section objects. Each section has a "heading" (string) and "bullets" array. \
        Each bullet has "text" (the bullet content) and "source_quote" (a SHORT verbatim quote of 5-15 words \
        copied exactly from the transcript that supports this bullet point, or null if no specific quote applies). \
        The quotes must appear VERBATIM in the transcript — do not paraphrase or fabricate quotes.

        For each action item, include a "source_quote": the verbatim words where the commitment was made (or null).

        IMPORTANT: Also include a flat "summary" field with the same content as markdown (### headings + - bullets) \
        for backward compatibility. Both "summary" and "summary_sections" must be present.

        Respond ONLY with valid JSON. No markdown fences. No commentary.
        """,
        isAdvancedMode: true,
        autoDetectRules: AutoDetectRules(titleKeywords: ["standup", "stand-up", "daily sync", "daily check"]),
        isBuiltIn: true
    )

    static let builtInTemplates: [MeetingTemplate] = [general, oneOnOne, brainstorm, standup]
}
