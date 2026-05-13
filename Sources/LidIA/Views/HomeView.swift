import SwiftUI
import SwiftData

/// Home detail — "What needs your attention" dashboard.
/// Meetings belong in the Meetings tab, not here.
struct HomeView: View {
    @Query(filter: #Predicate<ActionItem> { !$0.isCompleted })
    private var openActionItems: [ActionItem]
    @Query(filter: #Predicate<InboxNotification> { !$0.isRead }, sort: \InboxNotification.createdAt, order: .reverse)
    private var unreadNotifications: [InboxNotification]
    @Query(sort: \Meeting.date, order: .reverse)
    private var meetings: [Meeting]

    @Environment(AppSettings.self) private var settings
    @Environment(RecordingSession.self) private var session
    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor
    @Environment(\.modelContext) private var modelContext

    var selectedFolder: String?
    var onSelectEvent: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onRecord: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onRecordAppleEvent: ((EventKitManager.CalendarEvent) -> Void)?
    var onSelectMeeting: ((Meeting) -> Void)?
    var onQuickNote: (() -> Void)?
    var onOpenActionItems: (() -> Void)?

    @State private var hoveredNudgeID: UUID?
    @State private var editingNudgeID: UUID?
    @State private var editDraft: String = ""
    @State private var dispatchStatus: [UUID: String] = [:]  // "sending", "sent", "copied", "failed"

    // MARK: - Derived Data

    private var nextEvent: GoogleCalendarClient.CalendarEvent? {
        googleCalendarMonitor.upcomingEvents
            .filter { $0.end > .now }
            .sorted { $0.start < $1.start }
            .first
    }

    private var recentMeetingsCount: Int {
        let calendar = Calendar.current
        return meetings.filter { calendar.isDateInToday($0.date) && $0.status == .complete }.count
    }

    private var urgentActionItems: [ActionItem] {
        openActionItems.filter { $0.isUrgent }.prefix(3).map { $0 }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Recording banner
                if session.isRecording {
                    recordingBanner
                }

                // Greeting + stats
                greetingSection

                // Next up card
                if let event = nextEvent {
                    nextUpCard(event)
                }

                // For You nudges
                if !unreadNotifications.isEmpty {
                    nudgesSection
                }

                // Action items focus
                if !openActionItems.isEmpty {
                    actionItemsSection
                }

                // Quick actions
                quickActionsRow
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Home")
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.largeTitle.bold())

            HStack(spacing: 16) {
                if recentMeetingsCount > 0 {
                    Label("\(recentMeetingsCount) meetings today", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !openActionItems.isEmpty {
                    Label("\(openActionItems.count) open items", systemImage: "checklist")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if !unreadNotifications.isEmpty {
                    Label("\(unreadNotifications.count) for you", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = settings.displayName.components(separatedBy: " ").first ?? ""
        let prefix = switch hour {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        return name.isEmpty ? prefix : "\(prefix), \(name)"
    }

    // MARK: - Next Up

    private func nextUpCard(_ event: GoogleCalendarClient.CalendarEvent) -> some View {
        let eventColor = Color.fromHex(event.colorHex) ?? .orange

        return Button {
            onSelectEvent?(event)
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(eventColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Next up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(event.title)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(event.start, style: .relative)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !event.attendees.isEmpty {
                            Text("\u{00B7} \(event.attendees.count) attendees")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(14)

                Spacer()

                if event.meetingLink != nil {
                    Button("Join & Record", systemImage: "mic.fill") {
                        onRecord?(event)
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.regular)
                    .padding(.trailing, 14)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(eventColor.opacity(0.08)).interactive(), in: .rect(cornerRadius: 12))
    }

    // MARK: - Nudges

    private var nudgesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("For You", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
            }

            ForEach(unreadNotifications.prefix(5)) { notif in
                dispatcherCard(notif)
            }
        }
    }

    private func dispatcherCard(_ notif: InboxNotification) -> some View {
        let isHovered = hoveredNudgeID == notif.id
        let isEditing = editingNudgeID == notif.id
        let status = dispatchStatus[notif.id]

        return VStack(alignment: .leading, spacing: 8) {
            // Header: icon + title + edit/dismiss
            HStack(spacing: 8) {
                Image(systemName: notif.typeIcon)
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                Text(notif.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                if isHovered {
                    if notif.isDispatchable {
                        Button("Edit", systemImage: "pencil") {
                            editDraft = notif.draft ?? notif.body
                            editingNudgeID = isEditing ? nil : notif.id
                        }
                        .labelStyle(.iconOnly)
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Button("Dismiss", systemImage: "xmark") {
                        withAnimation { notif.isRead = true }
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }

            // Draft body (editable or static)
            if isEditing {
                TextField("Edit draft...", text: $editDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .lineLimit(3...6)
                    .padding(8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 6))
            } else if let draft = notif.draft {
                Text(draft)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            } else {
                Text(notif.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Recipient hint
            if let recipient = notif.recipient {
                HStack(spacing: 4) {
                    Image(systemName: "person")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(recipient)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Action buttons
            if notif.isDispatchable || status != nil {
                HStack(spacing: 8) {
                    if let status {
                        Label(
                            status == "sent" ? "Sent" : status == "copied" ? "Copied" : status == "failed" ? "Failed" : "Sending...",
                            systemImage: status == "sent" || status == "copied" ? "checkmark.circle.fill" : status == "failed" ? "xmark.circle" : "arrow.up.circle"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(status == "failed" ? .red : .green)
                    } else {
                        // Send via n8n
                        if settings.n8nEnabled && !settings.n8nWebhookURL.isEmpty {
                            Button {
                                sendViaN8n(notif)
                            } label: {
                                Label(n8nButtonLabel(notif.channel), systemImage: "paperplane.fill")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }

                        // Copy draft
                        Button {
                            copyDraft(notif)
                        } label: {
                            Label("Copy draft", systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(
            .regular.tint(.orange.opacity(isHovered ? 0.06 : 0.02)).interactive(),
            in: .rect(cornerRadius: 10)
        )
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.15)) { hoveredNudgeID = h ? notif.id : nil }
        }
    }

    // MARK: - Dispatch Actions

    private func sendViaN8n(_ notif: InboxNotification) {
        let draftText = editingNudgeID == notif.id ? editDraft : (notif.draft ?? notif.body)
        dispatchStatus[notif.id] = "sending"

        Task {
            let payload = N8nClient.DispatchPayload(
                channel: notif.channel ?? "reminder",
                recipient: notif.recipient,
                draft: draftText,
                ticketTitle: notif.ticketTitle,
                meetingTitle: notif.sourceMeetingTitle,
                actionItemTitle: notif.sourceActionItemTitle,
                actionItemID: notif.id.uuidString
            )

            let success = await N8nClient.sendDispatch(
                payload: payload,
                webhookURL: settings.n8nWebhookURL,
                authHeader: settings.n8nAuthHeader.isEmpty ? nil : settings.n8nAuthHeader
            )

            await MainActor.run {
                withAnimation {
                    dispatchStatus[notif.id] = success ? "sent" : "failed"
                    if success {
                        editingNudgeID = nil
                        // Auto-dismiss after delay
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            await MainActor.run {
                                withAnimation { notif.isRead = true }
                                dispatchStatus[notif.id] = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private func copyDraft(_ notif: InboxNotification) {
        let text = editingNudgeID == notif.id ? editDraft : (notif.draft ?? notif.body)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation { dispatchStatus[notif.id] = "copied" }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation { dispatchStatus[notif.id] = nil }
            }
        }
    }

    private func n8nButtonLabel(_ channel: String?) -> String {
        switch channel {
        case "slack": "Send to Slack"
        case "email": "Send email"
        case "ticket": "Create ticket"
        default: "Send via n8n"
        }
    }

    // MARK: - Action Items

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Action Items", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button {
                    onOpenActionItems?()
                } label: {
                    Text("View all \(openActionItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if !urgentActionItems.isEmpty {
                ForEach(urgentActionItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            if let assignee = item.assignee, !assignee.isEmpty {
                                Text(assignee)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.red.opacity(0.04)), in: .rect(cornerRadius: 8))
                }
            }

            // Summary bar
            Button {
                onOpenActionItems?()
            } label: {
                HStack(spacing: 10) {
                    Text("\(openActionItems.count) open")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("Open dashboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.orange.opacity(0.04)).interactive(), in: .rect(cornerRadius: 10))
        }
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            Button {
                onQuickNote?()
            } label: {
                Label("Quick Note", systemImage: "square.and.pencil")
                    .font(.subheadline)
            }
            .buttonStyle(.glass)

            if let event = nextEvent, event.meetingLink != nil {
                Button {
                    onRecord?(event)
                } label: {
                    Label("Join Next Meeting", systemImage: "video.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.top, 8)
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
                Button("View") { onSelectMeeting?(meeting) }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.red.opacity(0.15)).interactive(), in: .rect(cornerRadius: 10))
    }
}
