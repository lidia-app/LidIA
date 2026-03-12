import Foundation
import SwiftData

@MainActor
@Observable
final class RelationshipStore {
    struct PersonProfile: Identifiable {
        let id: String  // email (lowercased) when available, otherwise name lowercased
        let name: String
        let email: String?
        let meetingCount: Int
        let lastMet: Date
        let openActionItems: [ActionItem]
        let recentMeetings: [Meeting]
        let talkingPoints: [TalkingPoint]
    }

    static func parseAttendee(_ raw: String) -> (displayName: String?, email: String?) {
        let pattern = /^(.+?)\s*<([^>]+)>$/
        if let match = raw.wholeMatch(of: pattern) {
            return (String(match.1).trimmingCharacters(in: .whitespaces), String(match.2).lowercased())
        }
        if raw.contains("@") {
            return (nil, raw.lowercased().trimmingCharacters(in: .whitespaces))
        }
        return (raw.trimmingCharacters(in: .whitespaces), nil)
    }

    static func displayNameFromEmail(_ email: String) -> String {
        let prefix = email.split(separator: "@").first.map(String.init) ?? email
        return prefix
            .split(separator: ".")
            .flatMap { $0.split(separator: "-") }
            .flatMap { $0.split(separator: "_") }
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    func buildProfiles(modelContext: ModelContext) -> [PersonProfile] {
        let meetingDescriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let talkingPointDescriptor = FetchDescriptor<TalkingPoint>(
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )

        guard let meetings = try? modelContext.fetch(meetingDescriptor),
              let talkingPoints = try? modelContext.fetch(talkingPointDescriptor) else {
            return []
        }

        let completedMeetings = meetings.filter { $0.status == .complete }

        struct PersonData {
            var displayName: String?
            var email: String?
            var meetings: [Meeting] = []
        }

        var people: [String: PersonData] = [:]

        for meeting in completedMeetings {
            guard let attendees = meeting.calendarAttendees else { continue }
            for attendee in attendees {
                let trimmed = attendee.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let parsed = Self.parseAttendee(trimmed)
                let key: String
                if let email = parsed.email {
                    key = email
                } else if let name = parsed.displayName {
                    key = name.lowercased()
                } else {
                    continue
                }

                var data = people[key] ?? PersonData()
                if let email = parsed.email { data.email = email }
                if let name = parsed.displayName, !name.isEmpty {
                    data.displayName = name
                }
                data.meetings.append(meeting)
                people[key] = data
            }
        }

        let talkingPointsByPerson = Dictionary(grouping: talkingPoints.filter { !$0.isUsed }) {
            $0.personIdentifier.lowercased()
        }

        return people.map { (key, data) in
            let resolvedName: String
            if let displayName = data.displayName, !displayName.isEmpty {
                resolvedName = displayName
            } else if let email = data.email {
                resolvedName = Self.displayNameFromEmail(email)
            } else {
                resolvedName = key.capitalized
            }

            let sortedMeetings = data.meetings.sorted { $0.date > $1.date }
            let openActions = sortedMeetings.flatMap(\.actionItems).filter { item in
                guard !item.isCompleted else { return false }
                guard let assignee = item.assignee?.lowercased() else { return true }
                let nameLower = resolvedName.lowercased()
                return assignee.contains(nameLower)
                    || nameLower.contains(assignee)
                    || data.email.map { assignee.contains($0) } == true
                    || assignee.contains(key)
            }

            return PersonProfile(
                id: key,
                name: resolvedName,
                email: data.email,
                meetingCount: sortedMeetings.count,
                lastMet: sortedMeetings.first?.date ?? .distantPast,
                openActionItems: openActions,
                recentMeetings: Array(sortedMeetings.prefix(5)),
                talkingPoints: talkingPointsByPerson[key] ?? []
            )
        }
        .sorted { $0.lastMet > $1.lastMet }
    }

    func prepContext(for attendees: [String], modelContext: ModelContext) -> String {
        let profiles = buildProfiles(modelContext: modelContext)
        var context = ""
        for attendee in attendees {
            let parsed = Self.parseAttendee(attendee)
            let lookupKey: String
            if let email = parsed.email {
                lookupKey = email
            } else if let name = parsed.displayName {
                lookupKey = name.lowercased()
            } else {
                lookupKey = attendee.lowercased()
            }

            guard let profile = profiles.first(where: { $0.id == lookupKey }) else { continue }

            context += "## \(profile.name)\n"
            context += "- Met \(profile.meetingCount) times, last: \(profile.lastMet.formatted(date: .abbreviated, time: .omitted))\n"

            // Full summaries from last 3 meetings
            for meeting in profile.recentMeetings.prefix(3) {
                context += "### \(meeting.title) (\(meeting.date.formatted(date: .abbreviated, time: .omitted)))\n"
                let summary = MeetingContextRetrievalService.effectiveSummary(for: meeting)
                if !summary.isEmpty {
                    context += summary + "\n"
                }
            }

            // All open action items with details
            if !profile.openActionItems.isEmpty {
                context += "### Open Action Items\n"
                for item in profile.openActionItems {
                    context += "- \(item.title)"
                    if let assignee = item.assignee { context += " (assigned: \(assignee))" }
                    if let deadline = item.displayDeadline { context += " [due: \(deadline)]" }
                    context += "\n"
                }
            }

            // All talking points (fetch all, not just unused from profile)
            let allTalkingPoints = (try? modelContext.fetch(
                FetchDescriptor<TalkingPoint>(
                    predicate: #Predicate { $0.personIdentifier == lookupKey },
                    sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
                )
            )) ?? []
            if !allTalkingPoints.isEmpty {
                context += "### Talking Points\n"
                for tp in allTalkingPoints {
                    context += "- \(tp.content)\(tp.isUsed ? " [used]" : "")\n"
                }
            }

            context += "\n"
        }
        return context
    }
}
