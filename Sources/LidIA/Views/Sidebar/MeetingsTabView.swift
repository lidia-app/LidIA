import SwiftUI
import SwiftData

struct MeetingsTabView: View {
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor

    @Binding var selectedFolder: String?
    var onSelectMeeting: ((Meeting) -> Void)?
    var onSelectEvent: ((GoogleCalendarClient.CalendarEvent) -> Void)?

    private var upcomingEvents: [GoogleCalendarClient.CalendarEvent] {
        googleCalendarMonitor.upcomingEvents
            .filter { $0.end > .now }
            .sorted { $0.start < $1.start }
    }

    private var pastMeetings: [Meeting] {
        allMeetings.filter { meeting in
            guard meeting.status == .complete else { return false }
            if let folder = selectedFolder { return meeting.folder == folder }
            return true
        }
    }

    private var groupedPastMeetings: [(label: String, meetings: [Meeting])] {
        let calendar = Calendar.current
        let now = Date.now
        var buckets: [String: [Meeting]] = [:]
        var order: [String] = []

        for meeting in pastMeetings {
            let label = dateLabel(for: meeting.date, calendar: calendar, now: now)
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(meeting)
        }

        return order.map { (label: $0, meetings: buckets[$0]!) }
    }

    var body: some View {
        ScrollView {
            if upcomingEvents.isEmpty && groupedPastMeetings.isEmpty {
                ContentUnavailableView {
                    Label("No meetings yet", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Connect a calendar in Settings, or record your first meeting from the bottom-left + button.")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
            VStack(spacing: 12) {
                if !upcomingEvents.isEmpty {
                    SidebarSectionHeader("Upcoming")
                    VStack(spacing: 2) {
                        ForEach(upcomingEvents) { event in
                            SidebarRow(action: { onSelectEvent?(event) }) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.fromHex(event.colorHex) ?? .blue)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text(timeRange(start: event.start, end: event.end))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                ForEach(groupedPastMeetings, id: \.label) { group in
                    SidebarSectionHeader(group.label)
                    VStack(spacing: 2) {
                        ForEach(group.meetings) { meeting in
                            SidebarRow(action: { onSelectMeeting?(meeting) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            Text(meeting.date, format: .dateTime.hour().minute())
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if meeting.duration > 0 {
                                                Text(formatDuration(meeting.duration))
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Helpers

    private func timeRange(start: Date, end: Date) -> String {
        let s = start.formatted(.dateTime.hour().minute())
        let e = end.formatted(.dateTime.hour().minute())
        return "\(s) – \(e)"
    }

    private func dateLabel(for date: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}

// MARK: - Section Header (reusable)

struct SidebarSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}
