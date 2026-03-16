import Foundation

/// A Recipe is a post-meeting "lens" — a prompt applied to an already-completed meeting
/// to extract specific insights (coaching feedback, project briefs, follow-up emails, etc.).
/// Unlike MeetingTemplates which shape the summary during processing, Recipes work on
/// the finished summary + transcript + action items.
struct Recipe: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var name: String
    var emoji: String
    var description: String
    var prompt: String
    var category: Category

    enum Category: String, Codable, Sendable, CaseIterable {
        case coaching = "Coaching"
        case writing = "Writing"
        case analysis = "Analysis"
        case action = "Action"
    }

    static let builtIn: [Recipe] = [
        Recipe(
            name: "Coach Me",
            emoji: "🪞",
            description: "Analyze how you showed up — speaking ratio, question quality, listening signals",
            prompt: """
                Analyze this meeting from a communication coaching perspective. Evaluate:
                1. Speaking ratio — did the user talk too much or too little?
                2. Question quality — were questions open-ended and insightful?
                3. Listening signals — did they build on what others said?
                4. Action orientation — were next steps clear?
                Give specific examples from the transcript. Be direct but constructive. End with 2-3 actionable tips for next time.
                """,
            category: .coaching
        ),
        Recipe(
            name: "Write a Brief",
            emoji: "📋",
            description: "Turn the meeting into a structured project brief or PRD",
            prompt: """
                Convert this meeting into a structured Project Brief:
                - **Objective**: What are we trying to achieve?
                - **Context**: Why now? What's the background?
                - **Requirements**: What was agreed on?
                - **Open Questions**: What still needs answers?
                - **Next Steps**: Who does what by when?
                Keep it concise and actionable. Use bullet points.
                """,
            category: .writing
        ),
        Recipe(
            name: "Follow-up Email",
            emoji: "✉️",
            description: "Generate a professional follow-up email summarizing the meeting",
            prompt: """
                Write a concise follow-up email for this meeting. Include:
                - A brief summary of what was discussed (2-3 sentences)
                - Key decisions made
                - Action items with owners
                - Any deadlines mentioned
                Tone: professional but warm. Keep it under 200 words. Start with "Hi everyone," or "Hi [name]," for 1:1s.
                """,
            category: .writing
        ),
        Recipe(
            name: "Extract Decisions",
            emoji: "⚖️",
            description: "Pull out every decision made, with context and who approved",
            prompt: """
                Extract every decision made in this meeting. For each decision:
                - **Decision**: Clear statement of what was decided
                - **Made by**: Who made or approved it
                - **Context**: Why this decision was made
                - **Conditions**: Any caveats or dependencies
                Only include explicit decisions, not suggestions or ideas still under discussion.
                """,
            category: .analysis
        ),
        Recipe(
            name: "Executive Summary",
            emoji: "📊",
            description: "30-second summary for a busy manager",
            prompt: """
                Write a 30-second executive summary of this meeting:
                - One sentence: what was this meeting about
                - 2-3 bullets: key outcomes
                - Blockers or risks raised
                - What needs attention from leadership (if anything)
                Be extremely concise. No fluff. A busy executive should get the full picture in under 30 seconds.
                """,
            category: .analysis
        ),
        Recipe(
            name: "Action Plan",
            emoji: "🎯",
            description: "Create a prioritized action plan from the meeting outcomes",
            prompt: """
                Create a prioritized action plan from this meeting:
                1. List every commitment, task, and follow-up mentioned
                2. Assign priority (P0 = must do today, P1 = this week, P2 = soon)
                3. Group by owner/assignee
                4. Flag any dependencies between tasks
                5. Note any deadlines mentioned
                Format as a clean, copy-pasteable checklist.
                """,
            category: .action
        ),
    ]
}
