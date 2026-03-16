import SwiftUI
import SwiftData

struct HomeView: View {
    private static let dateHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingSession.self) private var session
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor

    var selectedFolder: String?
    var onSelectEvent: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onRecord: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onRecordAppleEvent: ((EventKitManager.CalendarEvent) -> Void)?
    var onSelectMeeting: ((Meeting) -> Void)?
    var onQuickNote: (() -> Void)?
    var onOpenActionItems: (() -> Void)?

    @State private var hoveredEventID: String?
    @State private var hoveredMeetingID: UUID?
    @State private var meetingToDelete: Meeting?
    @State private var showDeleteConfirmation = false
    @State private var cachedGroupedPastMeetings: [(header: String, meetings: [Meeting])] = []
    @State private var cachedGoogleEvents: [GoogleCalendarClient.CalendarEvent] = []
    @State private var cachedAppleEvents: [EventKitManager.CalendarEvent] = []
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Active recording banner
                if session.isRecording {
                    recordingBanner
                }

                // Upcoming meetings + Needs Attention (hidden during recording — banner takes priority)
                if !session.isRecording {
                    upcomingSection
                        .padding(.horizontal, 24)
                }

                Divider()
                    .padding(.horizontal, 24)

                // Past meetings
                pastMeetingsSection
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            cachedGroupedPastMeetings = computeGroupedPastMeetings()
            cachedGoogleEvents = computeUpcomingGoogleEvents()
            cachedAppleEvents = computeUpcomingAppleEvents()

            // Only fetch if cache is empty (avoids clearing events on tab switch)
            if cachedGoogleEvents.isEmpty,
               googleCalendarMonitor.isSignedIn,
               settings.googleCalendarEnabled {
                Task {
                    await googleCalendarMonitor.fetchWeek(containing: .now)
                }
            }
        }
        .onChange(of: googleCalendarMonitor.weekEvents) {
            cachedGoogleEvents = computeUpcomingGoogleEvents()
        }
        .onChange(of: eventKitManager.upcomingEvents) {
            cachedAppleEvents = computeUpcomingAppleEvents()
        }
        .onChange(of: meetings) {
            cachedGroupedPastMeetings = computeGroupedPastMeetings()
        }
        .onChange(of: selectedFolder) {
            cachedGroupedPastMeetings = computeGroupedPastMeetings()
        }
        .alert("Delete Meeting?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { meetingToDelete = nil }
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete {
                    modelContext.delete(meeting)
                    meetingToDelete = nil
                }
            }
        } message: {
            if let meeting = meetingToDelete {
                Text("\"\(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)\" and all its data will be permanently deleted.")
            }
        }
    }

    // MARK: - Recording Banner

    private var recordingBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .modifier(PulseEffect())

            Text("Recording")
                .font(.subheadline.bold())
                .foregroundStyle(.red)

            Text(formatTime(session.elapsedTime))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if let meeting = session.currentMeeting {
                Button {
                    onSelectMeeting?(meeting)
                } label: {
                    Text("View")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.red.opacity(0.15)).interactive(), in: .rect(cornerRadius: 10))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Upcoming Section

    private static let upcomingDayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private func computeUpcomingGoogleEvents() -> [GoogleCalendarClient.CalendarEvent] {
        Array(
            googleCalendarMonitor.weekEvents
                .filter { $0.end > .now }
                .sorted { $0.start < $1.start }
                .prefix(5)
        )
    }

    private func computeUpcomingAppleEvents() -> [EventKitManager.CalendarEvent] {
        Array(
            eventKitManager.upcomingEvents
                .filter { $0.end > .now }
                .sorted { $0.start < $1.start }
                .prefix(5)
        )
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming up")
                .font(.title.bold())

            if googleCalendarMonitor.isSignedIn && settings.googleCalendarEnabled {
                googleUpcomingContent
            } else if settings.calendarEnabled {
                appleUpcomingContent
            } else {
                emptyUpcomingState
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Google Upcoming

    @ViewBuilder
    private var googleUpcomingContent: some View {
        let upcoming = cachedGoogleEvents
        if upcoming.isEmpty {
            if googleCalendarMonitor.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                emptyUpcomingState
            }
        } else {
            let dayBreaks = dayBreakIndices(dates: upcoming.map(\.start))
            VStack(spacing: 8) {
                ForEach(upcoming.enumerated(), id: \.element.id) { index, event in
                    if dayBreaks.contains(index) {
                        dayLabel(for: event.start)
                    }
                    googleEventCard(event)
                }
            }
        }
    }

    // MARK: - Apple Upcoming

    @ViewBuilder
    private var appleUpcomingContent: some View {
        let upcoming = cachedAppleEvents
        if upcoming.isEmpty {
            emptyUpcomingState
        } else {
            let dayBreaks = dayBreakIndices(dates: upcoming.map(\.start))
            VStack(spacing: 8) {
                ForEach(upcoming.enumerated(), id: \.element.id) { index, event in
                    if dayBreaks.contains(index) {
                        dayLabel(for: event.start)
                    }
                    appleEventCard(event)
                }
            }
        }
    }

    /// Returns indices where the day changes (always includes index 0).
    private func dayBreakIndices(dates: [Date]) -> Set<Int> {
        let calendar = Calendar.current
        var result: Set<Int> = []
        var lastDay: Date?
        for (i, date) in dates.enumerated() {
            let day = calendar.startOfDay(for: date)
            if day != lastDay {
                result.insert(i)
                lastDay = day
            }
        }
        return result
    }

    private func dayLabel(for day: Date) -> some View {
        let calendar = Calendar.current
        let label: String
        if calendar.isDateInToday(day) {
            label = "Today"
        } else if calendar.isDateInTomorrow(day) {
            label = "Tomorrow"
        } else {
            label = Self.upcomingDayLabelFormatter.string(from: day)
        }
        return Text(label)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var emptyUpcomingState: some View {
        VStack(spacing: 12) {
            if !settings.calendarEnabled && !settings.googleCalendarEnabled {
                Text("Connect a calendar to see upcoming meetings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                        .font(.subheadline)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                Text("No meetings coming up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                onQuickNote?()
            } label: {
                Label("Record a quick note", systemImage: "square.and.pencil")
                    .font(.subheadline)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Google Event Card

    @ViewBuilder
    private func googleEventCard(_ event: GoogleCalendarClient.CalendarEvent) -> some View {
        let isHovered = hoveredEventID == event.id
        let isLive = event.start <= .now && event.end > .now

        Button {
            onSelectEvent?(event)
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.fromHex(event.colorHex) ?? .orange)
                    .frame(width: 4)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(event.title)
                                .font(.subheadline.bold())
                                .lineLimit(1)

                            if isLive {
                                liveBadge
                            }
                        }

                        HStack(spacing: 6) {
                            Text(timeRangeLabel(start: event.start, end: event.end))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !event.attendees.isEmpty {
                                Text("\u{00B7}")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                                attendeeAvatars(event.attendees)
                            }
                        }
                    }

                    Spacer()

                    if isHovered || isLive {
                        Button {
                            onRecord?(event)
                        } label: {
                            Label("Start now", systemImage: "mic.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
            .glassEffect(.regular.tint((Color.fromHex(event.colorHex) ?? .orange).opacity(0.1)).interactive(), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredEventID = hovering ? event.id : nil
            }
        }
    }

    // MARK: - Apple Event Card

    @ViewBuilder
    private func appleEventCard(_ event: EventKitManager.CalendarEvent) -> some View {
        let isHovered = hoveredEventID == event.id
        let isLive = event.start <= .now && event.end > .now

        Button {
            onRecordAppleEvent?(event)
        } label: {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.blue)
                .frame(width: 4)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)

                        if isLive {
                            liveBadge
                        }
                    }

                    HStack(spacing: 6) {
                        Text(timeRangeLabel(start: event.start, end: event.end))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !event.attendees.isEmpty {
                            Text("\u{00B7}")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                            attendeeAvatars(event.attendees)
                        }
                    }
                }

                Spacer()

                if isHovered || isLive {
                    Button {
                        onRecordAppleEvent?(event)
                    } label: {
                        Label("Start now", systemImage: "mic.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
        .glassEffect(.regular.tint(Color.blue.opacity(0.1)).interactive(), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredEventID = hovering ? event.id : nil
            }
        }
    }

    // MARK: - Live Badge

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("Live")
                .font(.caption2.bold())
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .glassEffect(.regular.tint(.green), in: .capsule)
    }

    // MARK: - Past Meetings Section

    private var pastMeetingsSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text("Past Meetings")
                .font(.title2.bold())
                .padding(.horizontal, 24)
                .padding(.top, 20)

            if cachedGroupedPastMeetings.isEmpty {
                Text("No meetings yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            } else {
                ForEach(cachedGroupedPastMeetings, id: \.header) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.header)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)

                        ForEach(section.meetings) { meeting in
                            pastMeetingRow(meeting)
                        }
                    }
                }
            }
        }
    }

    private func computeGroupedPastMeetings() -> [(header: String, meetings: [Meeting])] {
        let completed = meetings.filter { meeting in
            meeting.status != .recording
                && (selectedFolder == nil || meeting.folder == selectedFolder)
        }

        let calendar = Calendar.current
        var groups: [(header: String, meetings: [Meeting])] = []
        var buckets: [String: [Meeting]] = [:]
        var order: [String] = []

        for meeting in completed {
            let header: String
            if calendar.isDateInToday(meeting.date) {
                header = "Today"
            } else if calendar.isDateInYesterday(meeting.date) {
                header = "Yesterday"
            } else {
                header = Self.dateHeaderFormatter.string(from: meeting.date)
            }

            if buckets[header] == nil {
                order.append(header)
            }
            buckets[header, default: []].append(meeting)
        }

        for key in order {
            if let items = buckets[key] {
                groups.append((header: key, meetings: items))
            }
        }
        return groups
    }

    @ViewBuilder
    private func pastMeetingRow(_ meeting: Meeting) -> some View {
        Button {
            onSelectMeeting?(meeting)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(meeting.date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if meeting.duration > 0 {
                            Text(durationLabel(meeting.duration))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular, in: .capsule)
                        }

                        if let attendees = meeting.calendarAttendees, attendees.count > 1, meeting.duration > 0 {
                            let hours = Int(ceil(meeting.duration / 3600))
                            let personHours = hours * attendees.count
                            Text("\(personHours) person-hrs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        let openItems = meeting.actionItems.filter { !$0.isCompleted }.count
                        if openItems > 0 {
                            Label("\(openItems)", systemImage: "checklist")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let snippet = summarySnippet(for: meeting) {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if hoveredMeetingID == meeting.id {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredMeetingID = hovering ? meeting.id : nil
            }
        }
        .contextMenu {
            Button("Delete Meeting", role: .destructive) {
                meetingToDelete = meeting
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Attendee Avatars

    @ViewBuilder
    private func attendeeAvatars(_ attendees: [String]) -> some View {
        let visible = attendees.prefix(3)
        let overflow = attendees.count - visible.count

        HStack(spacing: -4) {
            ForEach(visible.enumerated(), id: \.offset) { _, name in
                AvatarView(name: name, size: 20)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.quaternary, in: Circle())
            }
        }
    }

    // MARK: - Helpers

    private static let timeRangeStartFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    private static let timeRangeEndFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private func timeRangeLabel(start: Date, end: Date) -> String {
        "\(Self.timeRangeStartFormatter.string(from: start)) \u{2013} \(Self.timeRangeEndFormatter.string(from: end))"
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining > 0 ? "\(hours)h \(remaining)m" : "\(hours)h"
    }

    private func summarySnippet(for meeting: Meeting) -> String? {
        if !meeting.summary.isEmpty {
            return String(meeting.summary.prefix(100))
        }
        if !meeting.notes.isEmpty {
            return String(meeting.notes.prefix(100))
        }
        return nil
    }

}
