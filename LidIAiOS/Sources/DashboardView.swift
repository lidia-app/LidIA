import SwiftUI
import SwiftData
import LidIAKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse)
    private var allMeetings: [Meeting]

    @Query(sort: \ActionItem.deadlineDate)
    private var allActionItems: [ActionItem]

    private var completedMeetings: [Meeting] {
        allMeetings.filter { $0.status != .recording }
    }

    private var openActionItems: [ActionItem] {
        allActionItems.filter { !$0.isCompleted }
    }


    private var todayMeetings: [Meeting] {
        let cal = Calendar.current
        return completedMeetings.filter { cal.isDateInToday($0.date) }
    }

    private var recentMeetings: [Meeting] {
        completedMeetings.prefix(10).filter { !Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    todaySection
                    actionItemsSection
                    recentSection
                }
                .padding()
            }
            .navigationTitle("LidIA")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today", systemImage: "calendar")
                .font(.title2.bold())

            if todayMeetings.isEmpty {
                ContentUnavailableView {
                    Label("No meetings today", systemImage: "checkmark.circle")
                } description: {
                    Text("Enjoy your free day!")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            } else {
                ForEach(todayMeetings) { meeting in
                    NavigationLink {
                        MeetingDetailiOSView(meeting: meeting)
                    } label: {
                        meetingCard(meeting)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Action Items", systemImage: "checklist")
                .font(.title2.bold())

            if openActionItems.isEmpty {
                Text("All caught up!")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(openActionItems.prefix(8)) { item in
                    actionItemRow(item)
                }
                if openActionItems.count > 8 {
                    Text("\(openActionItems.count - 8) more...")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !recentMeetings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Recent", systemImage: "clock")
                    .font(.title2.bold())

                ForEach(recentMeetings) { meeting in
                    NavigationLink {
                        MeetingDetailiOSView(meeting: meeting)
                    } label: {
                        meetingCard(meeting)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Components

    private func meetingCard(_ meeting: Meeting) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(meeting.date, style: .time)
                    if meeting.duration > 0 {
                        Text("\(Int(meeting.duration / 60))m")
                    }
                    if !meeting.actionItems.isEmpty {
                        Label("\(meeting.actionItems.count)", systemImage: "checklist")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func actionItemRow(_ item: ActionItem) -> some View {
        HStack {
            Button {
                item.isCompleted = true
                try? modelContext.save()
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let assignee = item.assignee {
                        Text(assignee)
                    }
                    if let deadline = item.displayDeadline {
                        Text(deadline)
                            .foregroundStyle(isOverdue(item) ? .red : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }


    private func isOverdue(_ item: ActionItem) -> Bool {
        guard let date = item.deadlineDate else { return false }
        return date < .now
    }
}
