import SwiftUI
import SwiftData

// MARK: - Shared Helpers

private func timeUntil(_ date: Date) -> String {
    let interval = date.timeIntervalSinceNow
    if interval < 0 { return "Now" }
    let minutes = Int(interval / 60)
    if minutes < 1 { return "Now" }
    if minutes < 60 { return "in \(minutes) min" }
    let hours = minutes / 60
    return "in \(hours)h \(minutes % 60)m"
}

struct MenuBarView: View {
    @Environment(RecordingSession.self) private var session
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor
    @Environment(MeetingDetector.self) private var meetingDetector
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]

    private var recentMeetings: [Meeting] {
        allMeetings.filter { $0.status == .complete }
    }

    private var openActionItems: [(item: ActionItem, meetingTitle: String)] {
        recentMeetings.prefix(10).flatMap { meeting in
            meeting.actionItems
                .filter { !$0.isCompleted }
                .map { (item: $0, meetingTitle: meeting.title) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.isRecording {
                        recordingSection
                    }

                    if hasUpcomingEvents {
                        comingUpSection
                    }

                    quickActionsSection

                    if !openActionItems.isEmpty {
                        actionItemsSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .frame(width: 320, height: 480)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Image(systemName: "ear.and.waveform")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("LidIA")
                .font(.headline)
            Spacer()
            if openActionItems.count > 0 {
                Text("\(openActionItems.count) open")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .glassEffect(.regular.tint(.orange), in: .capsule)
            }
        }
        .padding()
    }

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recording", systemImage: "record.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)

            HStack {
                Text(session.currentMeeting?.title ?? "Untitled")
                    .font(.subheadline)
                Spacer()
                Text(formatElapsed(session.elapsedTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button("Stop Recording") {
                session.stopRecording(modelContext: modelContext, settings: settings)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding()
        .glassEffect(.regular.tint(.red.opacity(0.1)), in: .rect(cornerRadius: 8))
    }

    private var hasUpcomingEvents: Bool {
        if googleCalendarMonitor.isSignedIn && !googleCalendarMonitor.upcomingEvents.isEmpty {
            return true
        }
        return !eventKitManager.upcomingEvents.isEmpty
    }

    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coming Up")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if googleCalendarMonitor.isSignedIn && !googleCalendarMonitor.upcomingEvents.isEmpty {
                ForEach(googleCalendarMonitor.upcomingEvents.prefix(3)) { event in
                    MenuBarGoogleEventRow(event: event) {
                        joinAndRecord(googleEvent: event)
                    } onRecord: {
                        startRecordingFromGoogleEvent(event)
                    }
                }
            } else {
                ForEach(eventKitManager.upcomingEvents.prefix(3)) { event in
                    MenuBarEventRow(event: event) {
                        startRecordingFromEvent(event)
                    }
                }
            }
        }
    }

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            Button {
                startQuickNote()
            } label: {
                Label("Quick Note", systemImage: "mic.fill")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(session.isRecording)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action Items")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(openActionItems.prefix(8), id: \.item.id) { entry in
                MenuBarActionItemRow(
                    item: entry.item,
                    meetingTitle: entry.meetingTitle
                )
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func startQuickNote() -> Meeting {
        session.startRecording(modelContext: modelContext, settings: settings, meetingDetector: meetingDetector)
    }

    private func startRecordingFromEvent(_ event: EventKitManager.CalendarEvent) {
        session.startRecordingFromEvent(event, modelContext: modelContext, settings: settings, meetingDetector: meetingDetector)
    }

    private func startRecordingFromGoogleEvent(_ event: GoogleCalendarClient.CalendarEvent) {
        session.startRecordingFromGoogleEvent(event, modelContext: modelContext, settings: settings, meetingDetector: meetingDetector)
    }

    private func joinAndRecord(googleEvent event: GoogleCalendarClient.CalendarEvent) {
        if let link = event.meetingLink {
            NSWorkspace.shared.open(link)
        }
        startRecordingFromGoogleEvent(event)
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Row Views

struct MenuBarEventRow: View {
    let event: EventKitManager.CalendarEvent
    let onRecord: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timeUntil(event.start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if event.meetingLink != nil {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()

            if let link = event.meetingLink {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.caption)
                }
                .buttonStyle(.glass)
                .controlSize(.mini)
                .help("Join Meeting")
            }

            Button {
                onRecord()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Record")
        }
        .padding(.vertical, 4)
    }
}

struct MenuBarGoogleEventRow: View {
    let event: GoogleCalendarClient.CalendarEvent
    let onJoinAndRecord: () -> Void
    let onRecord: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timeUntil(event.start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if event.meetingLink != nil {
                Button {
                    onJoinAndRecord()
                } label: {
                    Label("Join", systemImage: "video.fill")
                        .font(.caption)
                }
                .buttonStyle(.glass)
                .controlSize(.mini)
                .help("Join + Record")
            }

            Button {
                onRecord()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Record")
        }
        .padding(.vertical, 4)
    }
}

struct MenuBarActionItemRow: View {
    @Bindable var item: ActionItem
    let meetingTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                item.isCompleted.toggle()
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                Text(meetingTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
