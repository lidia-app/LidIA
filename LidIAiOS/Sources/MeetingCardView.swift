import SwiftUI
import LidIAKit

struct MeetingCardView: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(meeting.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                if meeting.duration > 0 {
                    Label("\(Int(meeting.duration / 60))m", systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let attendees = meeting.calendarAttendees, !attendees.isEmpty {
                HStack(spacing: -6) {
                    ForEach(attendees.prefix(4), id: \.self) { attendee in
                        Circle()
                            .fill(Color(hue: Double(abs(attendee.hashValue) % 360) / 360.0, saturation: 0.6, brightness: 0.8))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Text(String(attendee.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                    }
                    if attendees.count > 4 {
                        Text("+\(attendees.count - 4)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.leading, 10)
                    }
                }
            }

            if !meeting.actionItems.isEmpty {
                let openCount = meeting.actionItems.filter { !$0.isCompleted }.count
                if openCount > 0 {
                    Label("\(openCount) open", systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
