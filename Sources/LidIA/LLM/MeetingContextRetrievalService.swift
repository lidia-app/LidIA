import Foundation

struct MeetingContextRetrievalService {
    static func relevantMeetings(for query: String, from meetings: [Meeting], limit: Int) -> [Meeting] {
        let q = query.lowercased()
        let tokens = Set(
            q.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 }
        )

        let scored: [(meeting: Meeting, score: Int)] = meetings.map { meeting in
            let title = meeting.title.lowercased()
            let summary = effectiveSummary(for: meeting).lowercased()
            let notes = meeting.notes.lowercased()
            let transcript = effectiveTranscript(for: meeting).lowercased()
            let attendees = Set((meeting.calendarAttendees ?? []).map { $0.lowercased() })

            var score = recencyScore(for: meeting.date)

            for token in tokens {
                if title.contains(token) { score += 5 }
                if summary.contains(token) { score += 4 }
                if notes.contains(token) { score += 3 }
                if transcript.contains(token) { score += 2 }
                if attendees.contains(where: { $0.contains(token) }) { score += 6 }
            }

            if q.contains("action") || q.contains("promise") || q.contains("todo") {
                score += meeting.actionItems.filter { !$0.isCompleted }.count * 2
            }

            return (meeting, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.meeting.date > rhs.meeting.date
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.meeting)
    }

    static func meetingsForAttendees(_ attendees: [String], in meetings: [Meeting], limit: Int = 12) -> [Meeting] {
        let normalized = Set(attendees.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard !normalized.isEmpty else {
            return Array(meetings.sorted { $0.date > $1.date }.prefix(limit))
        }

        let scored = meetings.compactMap { meeting -> (Meeting, Int)? in
            let meetingAttendees = Set((meeting.calendarAttendees ?? []).map { $0.lowercased() })
            let overlap = normalized.intersection(meetingAttendees).count
            guard overlap > 0 else { return nil }
            let score = overlap * 10 + recencyScore(for: meeting.date)
            return (meeting, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.date > rhs.0.date
                }
                return lhs.1 > rhs.1
            }
            .prefix(limit)
            .map { $0.0 }
    }

    static func buildPrepSummary(attendees: [String], meetings: [Meeting]) -> String {
        let related = meetingsForAttendees(attendees, in: meetings, limit: 6)
        guard !related.isEmpty else {
            return "No prior meeting context for this attendee set yet."
        }

        let openItems = related
            .flatMap(\.actionItems)
            .filter { !$0.isCompleted }

        let uniqueAttendees = attendees.prefix(3).joined(separator: ", ")
        let lastMeeting = related.first
        let lastLabel = lastMeeting.map { "Last: \($0.title) on \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? ""

        var parts: [String] = []
        if !uniqueAttendees.isEmpty {
            parts.append("With: \(uniqueAttendees)")
        }
        parts.append("\(related.count) related prior meetings")
        if !openItems.isEmpty {
            parts.append("\(openItems.count) open action item\(openItems.count == 1 ? "" : "s")")
        }
        if !lastLabel.isEmpty {
            parts.append(lastLabel)
        }

        return parts.joined(separator: " • ")
    }

    static func effectiveSummary(for meeting: Meeting) -> String {
        let edited = meeting.userEditedSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return edited.isEmpty ? meeting.summary : edited
    }

    static func effectiveTranscript(for meeting: Meeting) -> String {
        let edited = meeting.userEditedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return edited.isEmpty ? meeting.refinedTranscript : edited
    }

    private static func recencyScore(for date: Date) -> Int {
        let days = max(0, Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0)
        switch days {
        case 0...2: return 8
        case 3...7: return 6
        case 8...14: return 4
        case 15...30: return 2
        default: return 1
        }
    }
}
