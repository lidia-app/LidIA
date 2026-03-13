import SwiftData
import SwiftUI

struct EditableActionItemRow: View {
    @Bindable var item: ActionItem
    let meetingTitle: String?
    var onSelectMeeting: (() -> Void)?
    var onDelete: (() -> Void)?

    @Environment(AppSettings.self) private var settings
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(\.modelContext) private var modelContext

    @FocusState private var isTitleFocused: Bool
    @State private var titleDraft = ""
    @State private var deadlineDraft = Date()
    @State private var isShowingDeadlineEditor = false
    @State private var persistenceError: String?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(item.isCompleted ? "Mark incomplete" : "Mark complete", systemImage: item.isCompleted ? "checkmark.circle.fill" : "circle") {
                item.isCompleted.toggle()
                persistChanges()
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(item.isCompleted ? .green : .secondary)
            .font(.body)
            .buttonStyle(.borderless)

            // Priority indicator
            if item.priority != "none" {
                priorityBadge(item.priority, isAutoUrgent: item.isAutoUrgent)
            } else if item.isAutoUrgent {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField("Action item", text: $titleDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .strikethrough(item.isCompleted)
                    .lineLimit(2)
                    .focused($isTitleFocused)
                    .onSubmit(commitTitle)
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused { commitTitle() }
                    }

                // Single metadata line
                HStack(spacing: 6) {
                    if let assignee = item.assignee, !assignee.isEmpty {
                        Label(assignee, systemImage: "person")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let deadline = item.displayDeadline {
                        Button {
                            deadlineDraft = item.deadlineDate ?? defaultDeadline
                            isShowingDeadlineEditor = true
                        } label: {
                            Label(deadline, systemImage: "calendar")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)

                        Button("Clear deadline", systemImage: "xmark.circle.fill") {
                            item.setPreciseDeadline(nil)
                            persistChanges()
                        }
                        .labelStyle(.iconOnly)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            deadlineDraft = defaultDeadline
                            isShowingDeadlineEditor = true
                        } label: {
                            Label("Deadline", systemImage: "calendar.badge.plus")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                    }

                    if let suggested = item.suggestedDestination, suggested != "none" {
                        destinationPill(suggested: suggested)
                    }

                    if let meetingTitle, let onSelectMeeting {
                        Button(action: onSelectMeeting) {
                            Text(meetingTitle.isEmpty ? "Untitled" : meetingTitle)
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .popover(isPresented: $isShowingDeadlineEditor, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("Deadline", selection: $deadlineDraft, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                        HStack {
                            Button("Clear", role: .destructive) {
                                item.setPreciseDeadline(nil)
                                isShowingDeadlineEditor = false
                                persistChanges()
                            }
                            Spacer()
                            Button("Save") {
                                item.setPreciseDeadline(deadlineDraft)
                                isShowingDeadlineEditor = false
                                persistChanges()
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding()
                    .frame(width: 320)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Menu("Priority") {
                ForEach(["critical", "high", "medium", "low", "none"], id: \.self) { level in
                    Button {
                        item.priority = level
                        persistChanges()
                    } label: {
                        HStack {
                            Label(level.capitalized, systemImage: priorityIcon(level))
                            if item.priority == level { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDelete?()
            }
        }
        .onAppear {
            syncDraftsFromModel()
        }
        .onChange(of: item.title) { _, _ in
            if !isTitleFocused {
                syncDraftsFromModel()
            }
        }
        .alert("Action Item", isPresented: Binding(
            get: { persistenceError != nil },
            set: { if !$0 { persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "")
        }
    }

    private var defaultDeadline: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    }

    private func syncDraftsFromModel() {
        titleDraft = item.title
        deadlineDraft = item.deadlineDate ?? defaultDeadline
    }

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleDraft = item.title
            return
        }
        guard trimmed != item.title else { return }
        item.title = trimmed
        persistChanges()
    }

    @ViewBuilder
    private func destinationPill(suggested: String) -> some View {
        let isConfirmed = item.confirmedDestination != nil

        HStack(spacing: 4) {
            Menu {
                ForEach(["clickup", "notion", "reminder", "n8n", "none"], id: \.self) { dest in
                    Button {
                        item.confirmedDestination = dest == "none" ? nil : dest
                        item.suggestedDestination = dest == "none" ? nil : dest
                        persistChanges()
                    } label: {
                        HStack {
                            Text(destinationLabel(dest))
                            if item.confirmedDestination == dest || (item.confirmedDestination == nil && item.suggestedDestination == dest) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\u{2192} \(destinationLabel(item.confirmedDestination ?? suggested))")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isConfirmed ? destinationColor(item.confirmedDestination ?? suggested).opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !isConfirmed {
                Button("Confirm destination", systemImage: "checkmark.circle") {
                    item.confirmedDestination = suggested
                    persistChanges()
                }
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.green)
                .buttonStyle(.borderless)
                .help("Confirm destination")
            }
        }
    }

    private func destinationLabel(_ dest: String) -> String {
        switch dest {
        case "clickup": "ClickUp"
        case "notion": "Notion"
        case "reminder": "Reminder"
        case "n8n": "n8n"
        default: dest.capitalized
        }
    }

    private func destinationColor(_ dest: String) -> Color {
        switch dest {
        case "clickup": .purple
        case "notion": .blue
        case "reminder": .orange
        case "n8n": .green
        default: .secondary
        }
    }

    @ViewBuilder
    private func priorityBadge(_ level: String, isAutoUrgent: Bool) -> some View {
        let color = priorityColor(level, isAutoUrgent: isAutoUrgent)
        Text(priorityLabel(level))
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 16)
    }

    private func priorityLabel(_ level: String) -> String {
        switch level {
        case "critical": "!!!"
        case "high": "!!"
        case "medium": "!"
        case "low": "\u{2193}"
        default: ""
        }
    }

    private func priorityIcon(_ level: String) -> String {
        switch level {
        case "critical": "exclamationmark.3"
        case "high": "exclamationmark.2"
        case "medium": "exclamationmark"
        case "low": "arrow.down"
        default: "minus"
        }
    }

    private func priorityColor(_ level: String, isAutoUrgent: Bool) -> Color {
        switch level {
        case "critical": .red
        case "high": .orange
        case "medium": .yellow
        case "low": .blue
        default: isAutoUrgent ? .yellow : .secondary.opacity(0.3)
        }
    }

    private func priorityHelpText(_ level: String, isAutoUrgent: Bool) -> String {
        if level != "none" { return "Priority: \(level.capitalized)" }
        if isAutoUrgent { return "Auto-urgent (deadline \u{2264}48h)" }
        return "Set priority"
    }

    private func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            persistenceError = error.localizedDescription
            return
        }

        guard settings.remindersEnabled else { return }
        Task { @MainActor in
            let reminderID = await eventKitManager.syncReminder(
                reminderID: item.reminderID,
                title: item.title,
                deadlineText: item.displayDeadline,
                deadlineDate: item.deadlineDate,
                isCompleted: item.isCompleted
            )
            if item.reminderID != reminderID {
                item.reminderID = reminderID
                try? modelContext.save()
            }
        }
    }
}
