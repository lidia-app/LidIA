import SwiftUI
import SwiftData

struct CalendarEventDetailView: View {
    let event: GoogleCalendarClient.CalendarEvent
    let onRecord: (String) -> Void
    var onBack: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var notes = ""
    @State private var prepContext = ""
    @State private var pendingItems: [(item: ActionItem, meetingTitle: String)] = []
    @State private var showAttendeesPopover = false

    private let relationshipStore = RelationshipStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                countdown
                chips
                if !pendingItems.isEmpty {
                    pendingActionItemsSection
                }
                if !prepContext.isEmpty {
                    prepSection
                }
                notesSection
                actionButtons
            }
            .padding(32)
            .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            prepContext = relationshipStore.prepContext(for: event.attendees, modelContext: modelContext)
            loadPendingActionItems()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    Label("Home", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text(event.title)
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }

    // MARK: - Countdown

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let interval = event.start.timeIntervalSince(now)
            let endInterval = event.end.timeIntervalSince(now)

            if endInterval <= 0 {
                // Already ended — don't show
                EmptyView()
            } else {
                Text(countdownText(interval: interval))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(countdownColor(interval: interval).opacity(0.15), in: Capsule())
                    .foregroundStyle(countdownColor(interval: interval))
            }
        }
    }

    private func countdownText(interval: TimeInterval) -> String {
        if interval <= 0 {
            let ago = -interval
            if ago < 60 {
                return "Starting now"
            }
            let minutes = Int(ago / 60)
            if minutes < 60 {
                return "Started \(minutes) min ago"
            }
            let hours = minutes / 60
            return "Started \(hours)h \(minutes % 60)m ago"
        }
        let minutes = Int(interval / 60)
        if minutes < 1 {
            return "Starting now"
        } else if minutes < 60 {
            return "In \(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "In \(hours) hour\(hours == 1 ? "" : "s")"
            }
            return "In \(hours)h \(remainingMinutes)m"
        }
    }

    private func countdownColor(interval: TimeInterval) -> Color {
        if interval <= 0 {
            return .green
        } else if interval <= 15 * 60 {
            return .orange
        } else {
            return .secondary
        }
    }

    // MARK: - Chips

    private var chips: some View {
        HStack(spacing: 8) {
            Label(dateChipLabel, systemImage: "calendar")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: Capsule())

            Label(timeRangeLabel, systemImage: "clock")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: Capsule())

            if !event.attendees.isEmpty {
                Button {
                    showAttendeesPopover.toggle()
                } label: {
                    Label(attendeeChipLabel, systemImage: "person.2")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showAttendeesPopover) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(event.attendees, id: \.self) { attendee in
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(attendee)
                                    .font(.callout)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var dateChipLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(event.start) {
            return "Today"
        } else if calendar.isDateInTomorrow(event.start) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: event.start)
        }
    }

    private var timeRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
    }

    private var attendeeChipLabel: String {
        let first = event.attendees[0]
        if event.attendees.count == 1 {
            return first
        }
        return "\(first) + \(event.attendees.count - 1) more"
    }

    // MARK: - Pending Action Items with Attendees

    private var pendingActionItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pending with attendees", systemImage: "checklist")
                .font(.headline)

            ForEach(pendingItems, id: \.item.id) { entry in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.item.title)
                            .font(.callout)
                        HStack(spacing: 4) {
                            if let assignee = entry.item.assignee {
                                Text(assignee)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("from \(entry.meetingTitle)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func loadPendingActionItems() {
        let descriptor = FetchDescriptor<ActionItem>(
            predicate: #Predicate<ActionItem> { !$0.isCompleted }
        )
        guard let allOpen = try? modelContext.fetch(descriptor) else { return }

        let lowercasedAttendees = event.attendees.map { $0.lowercased() }
        pendingItems = allOpen.compactMap { item in
            guard let assignee = item.assignee?.lowercased(), !assignee.isEmpty else { return nil }
            let matches = lowercasedAttendees.contains { attendee in
                attendee.contains(assignee) || assignee.contains(attendee)
            }
            guard matches else { return nil }
            let meetingTitle = item.meeting?.title ?? "Unknown"
            return (item: item, meetingTitle: meetingTitle)
        }
    }

    // MARK: - Prep Section

    private var prepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Meeting Prep", systemImage: "lightbulb")
                .font(.headline)

            Text(LocalizedStringKey(prepContext))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            TextEditor(text: $notes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 120)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onRecord(notes)
            } label: {
                Label("Record", systemImage: "mic.fill")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            if let link = event.meetingLink {
                Button {
                    NSWorkspace.shared.open(link)
                    onRecord(notes)
                } label: {
                    Label("Join + Record", systemImage: "video.fill")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
