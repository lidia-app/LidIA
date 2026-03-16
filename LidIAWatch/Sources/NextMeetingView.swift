import SwiftUI
import SwiftData
import LidIAKit

struct NextMeetingView: View {
    @Query(sort: \Meeting.date, order: .forward) private var allMeetings: [Meeting]

    private var nextMeeting: Meeting? {
        allMeetings.first { $0.date > .now && $0.status != .recording }
    }

    var body: some View {
        if let meeting = nextMeeting {
            VStack(alignment: .leading, spacing: 8) {
                Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                    .font(.headline)
                    .lineLimit(3)

                Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
                    Text("\(attendees.count) attendees")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Next Meeting")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No upcoming meetings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Next Meeting")
        }
    }
}
