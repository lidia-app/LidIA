import SwiftUI
import SwiftData

struct HomeTabView: View {
    var onSelectMeeting: ((Meeting) -> Void)?
    var onSelectEvent: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onRecord: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onOpenActionItems: (() -> Void)?
    var onOpenPeople: (() -> Void)?
    var onSelectMeetingByID: ((UUID) -> Void)?
    var onOpenMeetings: (() -> Void)?

    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor
    @Environment(\.modelContext) private var modelContext

    @AppStorage("sidebar.home.comingUpCollapsed") private var comingUpCollapsed = false
    @AppStorage("sidebar.home.recentsCollapsed") private var recentsCollapsed = false
    @AppStorage("sidebar.home.actionsCollapsed") private var actionsCollapsed = false
    @AppStorage("sidebar.home.dispatcherCollapsed") private var dispatcherCollapsed = false

    @Query(sort: \Meeting.date, order: .reverse)
    private var allMeetings: [Meeting]

    @Query(filter: #Predicate<ActionItem> { !$0.isCompleted })
    private var openActionItems: [ActionItem]

    @Query(filter: #Predicate<InboxNotification> { !$0.isRead }, sort: \InboxNotification.createdAt, order: .reverse)
    private var unreadNotifications: [InboxNotification]

    private var upcomingEvents: [GoogleCalendarClient.CalendarEvent] {
        Array(
            googleCalendarMonitor.upcomingEvents
                .filter { $0.end > .now }
                .sorted { $0.start < $1.start }
                .prefix(2)
        )
    }

    private var recentMeetings: [Meeting] {
        Array(allMeetings.filter { $0.status == .complete || $0.status == .recording }.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Coming Up (max 2, then "Show more")
                SidebarSection(title: "Coming Up", icon: "calendar", isCollapsed: $comingUpCollapsed) {
                    if upcomingEvents.isEmpty {
                        SidebarEmptyRow("No upcoming events")
                    } else {
                        ForEach(upcomingEvents) { event in
                            EventRow(
                                event: event,
                                onSelect: { onSelectEvent?(event) },
                                onJoin: { onRecord?(event) }
                            )
                        }

                        if googleCalendarMonitor.upcomingEvents.filter({ $0.end > .now }).count > 2 {
                            SidebarRow(action: { onOpenMeetings?() }) {
                                HStack {
                                    Spacer()
                                    Text("Show more")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // For You (dispatcher)
                if !unreadNotifications.isEmpty {
                    SidebarSection(title: "For You", icon: "sparkles", isCollapsed: $dispatcherCollapsed, badgeCount: unreadNotifications.count) {
                        ForEach(unreadNotifications.prefix(3)) { notif in
                            DispatcherCard(
                                notification: notif,
                                onAction: {
                                    notif.isRead = true
                                    if let meetingID = notif.meetingID {
                                        onSelectMeetingByID?(meetingID)
                                    }
                                },
                                onDismiss: {
                                    withAnimation { notif.isRead = true }
                                }
                            )
                        }
                    }
                }

                // Recents
                SidebarSection(title: "Recents", icon: "clock", isCollapsed: $recentsCollapsed) {
                    if recentMeetings.isEmpty {
                        SidebarEmptyRow("No recent meetings")
                    } else {
                        ForEach(recentMeetings) { meeting in
                            SidebarRow(action: { onSelectMeeting?(meeting) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text(relativeAge(meeting.date))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Action Items
                SidebarSection(
                    title: "Action Items",
                    icon: "checklist",
                    isCollapsed: $actionsCollapsed,
                    badgeCount: openActionItems.count,
                    onBadgeTap: { onOpenActionItems?() }
                ) {
                    if openActionItems.isEmpty {
                        SidebarEmptyRow("No open action items")
                    } else {
                        ForEach(openActionItems.prefix(5)) { item in
                            SidebarRow(action: {
                                if let meeting = item.meeting { onSelectMeeting?(meeting) }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "circle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Text(item.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                            }
                        }

                        if openActionItems.count > 5 {
                            SidebarRow(action: { onOpenActionItems?() }) {
                                HStack {
                                    Spacer()
                                    Text("See all \(openActionItems.count) items")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // People
                SidebarRow(action: { onOpenPeople?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("All People")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// Stable relative age that doesn't tick second-by-second (e.g. "4m ago", "2h ago", "yesterday").
    /// Prevents past meetings from looking like an active in-progress timer.
    private func relativeAge(_ date: Date) -> String {
        let now = Date.now
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 {
            let m = Int(interval / 60)
            return "\(m)m ago"
        }
        if Calendar.current.isDateInToday(date) {
            let h = Int(interval / 3600)
            return "\(h)h ago"
        }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Sidebar Section (glass card with collapsible header)

struct SidebarSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isCollapsed: Bool
    var badgeCount: Int = 0
    var onBadgeTap: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if badgeCount > 0 {
                        Button {
                            onBadgeTap?()
                        } label: {
                            Text("\(badgeCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.orange, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(spacing: 2) {
                    content
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Sidebar Row (glass hover)

struct SidebarRow<Content: View>: View {
    var action: () -> Void
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                .opacity(isHovered ? 1 : 0)
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Empty Row

struct SidebarEmptyRow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

// MARK: - Dispatcher Card

/// Compact dispatcher card for sidebar — shows draft preview, channel badge, copy action.
struct DispatcherCard: View {
    let notification: InboxNotification
    var onAction: () -> Void
    var onDismiss: () -> Void
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: notification.typeIcon)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(notification.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .opacity(isHovered ? 1 : 0)
            }

            // Draft preview or body
            if let draft = notification.draft {
                Text(draft)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(notification.body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Channel badge + actions — always present in layout, opacity-gated on hover
            HStack(spacing: 6) {
                if let channel = notification.channel {
                    Text(channelLabel(channel))
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if copied {
                    Text("Copied")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green)
                } else if notification.isDispatchable {
                    Button {
                        let text = notification.draft ?? notification.body
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            await MainActor.run { copied = false }
                        }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
                }

                if notification.meetingID != nil {
                    Button {
                        onAction()
                    } label: {
                        Label("Open", systemImage: "arrow.right")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .opacity(isHovered ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(.rect(cornerRadius: 8))
        .glassEffect(
            .regular.tint(.orange.opacity(isHovered ? 0.08 : 0.03)).interactive(),
            in: .rect(cornerRadius: 8)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private func channelLabel(_ channel: String) -> String {
        switch channel {
        case "slack": "Slack"
        case "email": "Email"
        case "ticket": "Ticket"
        case "reminder": "Reminder"
        default: channel
        }
    }
}
