import Foundation
import SwiftData

enum DemoDataSeeder {
    static var isDemoMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
    }

    @MainActor
    static func seed(context: ModelContext) {
        // In-memory store is empty by default — no need to delete anything
        let cal = Calendar.current
        let now = Date()

        // --- Past Meetings ---

        let standup = Meeting(
            title: "Team Standup",
            date: cal.date(byAdding: .hour, value: -2, to: now)!
        )
        standup.status = .complete
        standup.duration = 900 // 15m
        standup.summary = """
        ## Key Updates
        - **Frontend**: Alex finished the onboarding flow redesign, ready for QA
        - **Backend**: Maria resolved the API rate limiting issue in production
        - **Infrastructure**: DevOps team completed the staging environment migration to ARM instances

        ## Blockers
        - Design team needs final copy for the pricing page by EOD Thursday
        - CI pipeline flaky on the integration test suite — investigating timeout config

        ## Decisions
        - Moving sprint demo to Friday 3pm to accommodate the London team
        - Approved the new error monitoring dashboard in Grafana
        """
        standup.calendarAttendees = ["Alex Chen", "Maria Santos", "James Kim", "You"]
        context.insert(standup)

        let action1 = ActionItem(title: "Review onboarding flow PR #342", assignee: "You", deadline: "Tomorrow")
        action1.deadlineDate = cal.date(byAdding: .day, value: 1, to: now)
        action1.priority = "high"
        action1.meeting = standup
        standup.actionItems.append(action1)

        let action2 = ActionItem(title: "Send pricing page copy to design team", assignee: "You", deadline: "Thursday")
        action2.deadlineDate = cal.date(byAdding: .day, value: 2, to: now)
        action2.priority = "critical"
        action2.meeting = standup
        standup.actionItems.append(action2)

        let action3 = ActionItem(title: "Investigate CI timeout configuration", assignee: "James Kim")
        action3.priority = "medium"
        action3.meeting = standup
        standup.actionItems.append(action3)

        // Client call yesterday
        let clientCall = Meeting(
            title: "Client Call — Acme Corp",
            date: cal.date(byAdding: .day, value: -1, to: now)!
        )
        clientCall.status = .complete
        clientCall.duration = 2700 // 45m
        clientCall.summary = """
        ## Overview
        Quarterly review with Acme Corp. Discussed Q1 results, upcoming feature requests, and renewal timeline.

        ## Key Discussion Points
        - **Q1 Performance**: 40% increase in API usage, 99.97% uptime achieved
        - **Feature Requests**: SSO integration (priority), bulk export API, custom webhooks
        - **Renewal**: Contract renewal in 60 days — they want a 2-year deal with volume discount
        - **Technical**: Asked about SOC 2 Type II status — we're 3 weeks from completion

        ## Next Steps
        - Send SOC 2 timeline to their compliance team
        - Draft proposal for 2-year renewal with tiered pricing
        - Schedule technical deep-dive for SSO requirements
        """
        clientCall.calendarAttendees = ["Sarah Johnson (Acme)", "Mike Chen (Acme)", "You", "Lisa Park"]
        context.insert(clientCall)

        let action4 = ActionItem(title: "Draft 2-year renewal proposal for Acme", assignee: "You", deadline: "Next Monday")
        action4.deadlineDate = cal.date(byAdding: .day, value: 5, to: now)
        action4.priority = "high"
        action4.meeting = clientCall
        clientCall.actionItems.append(action4)

        let action5 = ActionItem(title: "Send SOC 2 timeline to Acme compliance", assignee: "Lisa Park", deadline: "Friday")
        action5.deadlineDate = cal.date(byAdding: .day, value: 3, to: now)
        action5.priority = "medium"
        action5.isCompleted = true
        action5.meeting = clientCall
        clientCall.actionItems.append(action5)

        let action6 = ActionItem(title: "Schedule SSO deep-dive with Acme engineering", assignee: "You")
        action6.priority = "low"
        action6.suggestedDestination = "notion"
        action6.meeting = clientCall
        clientCall.actionItems.append(action6)

        // Product review 2 days ago
        let productReview = Meeting(
            title: "Product Review — Q2 Roadmap",
            date: cal.date(byAdding: .day, value: -2, to: now)!
        )
        productReview.status = .complete
        productReview.duration = 3600 // 60m
        productReview.summary = """
        ## Q2 Priorities
        1. **Self-serve onboarding** — reduce time-to-value from 3 days to 30 minutes
        2. **API v2** — GraphQL layer, breaking changes communicated 90 days ahead
        3. **Mobile app** — iOS first, read-only dashboard + push notifications

        ## Decisions
        - Deprioritized the Slack integration — low demand from enterprise accounts
        - Approved hiring 2 senior frontend engineers for the onboarding rewrite
        - Moving to bi-weekly releases starting April

        ## Risks
        - API v2 timeline is tight if we keep the backwards compatibility requirement
        - Mobile app depends on the new auth system shipping in March
        """
        productReview.calendarAttendees = ["You", "Elena Ruiz", "Tom Bradley", "Priya Patel", "David Kim"]
        context.insert(productReview)

        // 1:1 from 3 days ago
        let oneOnOne = Meeting(
            title: "1:1 with Elena",
            date: cal.date(byAdding: .day, value: -3, to: now)!
        )
        oneOnOne.status = .complete
        oneOnOne.duration = 1800 // 30m
        oneOnOne.summary = """
        ## Discussion
        - Elena is interested in leading the API v2 project — discussed scope and timeline
        - She completed the AWS certification last week
        - Feedback: wants more visibility into product decisions, feels out of the loop sometimes
        - Career goal: Staff Engineer track — reviewed the promotion criteria together

        ## Action Items
        - Add Elena to the product review invite list going forward
        - Set up a shadow session with the SRE team for on-call exposure
        """
        oneOnOne.calendarAttendees = ["You", "Elena Ruiz"]
        context.insert(oneOnOne)

        let action7 = ActionItem(title: "Add Elena to product review invites", assignee: "You")
        action7.priority = "medium"
        action7.isCompleted = true
        action7.meeting = oneOnOne
        oneOnOne.actionItems.append(action7)

        let action8 = ActionItem(title: "Set up SRE shadow session for Elena", assignee: "You", deadline: "Next week")
        action8.deadlineDate = cal.date(byAdding: .day, value: 7, to: now)
        action8.priority = "low"
        action8.meeting = oneOnOne
        oneOnOne.actionItems.append(action8)

        try? context.save()
    }

    static func fakeUpcomingEvents() -> [GoogleCalendarClient.CalendarEvent] {
        let cal = Calendar.current
        let now = Date()

        // A "live" meeting happening now
        let liveStart = cal.date(byAdding: .minute, value: -15, to: now)!
        let liveEnd = cal.date(byAdding: .minute, value: 45, to: now)!

        // Next meeting in 2 hours
        let nextStart = cal.date(byAdding: .hour, value: 2, to: now)!
        let nextEnd = cal.date(byAdding: .hour, value: 3, to: now)!

        // Tomorrow morning
        var tomorrowComponents = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: 1, to: now)!)
        tomorrowComponents.hour = 10
        tomorrowComponents.minute = 0
        let tomorrowMorning = cal.date(from: tomorrowComponents)!
        let tomorrowMorningEnd = cal.date(byAdding: .minute, value: 30, to: tomorrowMorning)!

        // Tomorrow afternoon
        tomorrowComponents.hour = 14
        let tomorrowAfternoon = cal.date(from: tomorrowComponents)!
        let tomorrowAfternoonEnd = cal.date(byAdding: .hour, value: 1, to: tomorrowAfternoon)!

        // Day after tomorrow
        var dayAfterComponents = cal.dateComponents([.year, .month, .day], from: cal.date(byAdding: .day, value: 2, to: now)!)
        dayAfterComponents.hour = 9
        dayAfterComponents.minute = 0
        let dayAfter = cal.date(from: dayAfterComponents)!
        let dayAfterEnd = cal.date(byAdding: .minute, value: 45, to: dayAfter)!

        return [
            GoogleCalendarClient.CalendarEvent(
                id: "demo-1",
                title: "Sprint Planning",
                start: liveStart,
                end: liveEnd,
                attendees: ["Alex Chen", "Maria Santos", "James Kim", "Priya Patel"],
                meetingLink: nil,
                colorHex: "#4CAF50"
            ),
            GoogleCalendarClient.CalendarEvent(
                id: "demo-2",
                title: "1:1 with Elena",
                start: nextStart,
                end: nextEnd,
                attendees: ["Elena Ruiz"],
                meetingLink: nil,
                colorHex: "#2196F3"
            ),
            GoogleCalendarClient.CalendarEvent(
                id: "demo-3",
                title: "Design Review — Onboarding",
                start: tomorrowMorning,
                end: tomorrowMorningEnd,
                attendees: ["Tom Bradley", "Lisa Park"],
                meetingLink: nil,
                colorHex: "#FF9800"
            ),
            GoogleCalendarClient.CalendarEvent(
                id: "demo-4",
                title: "Client Sync — Acme Corp",
                start: tomorrowAfternoon,
                end: tomorrowAfternoonEnd,
                attendees: ["Sarah Johnson", "Mike Chen", "Lisa Park"],
                meetingLink: nil,
                colorHex: "#9C27B0"
            ),
            GoogleCalendarClient.CalendarEvent(
                id: "demo-5",
                title: "All Hands",
                start: dayAfter,
                end: dayAfterEnd,
                attendees: ["Everyone"],
                meetingLink: nil,
                colorHex: "#F44336"
            ),
        ]
    }
}
