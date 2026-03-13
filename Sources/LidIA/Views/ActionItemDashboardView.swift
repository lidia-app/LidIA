import SwiftData
import SwiftUI

struct ActionItemDashboardView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Binding var selectedMeeting: Meeting?

    @State private var showCompleted = false
    @State private var showMyItemsOnly = true
    @State private var filterText = ""
    @State private var isSyncingToNotion = false
    @State private var alertTitle: String = "Action Items"
    @State private var alertMessage: String?
    @State private var priorityFilter = "all"
    @State private var hoveredItemID: UUID?
    @State private var cachedActionItems: [(ActionItem, Meeting)] = []
    @State private var isDispatching = false
    @State private var newActionItemTitle = ""

    private var filteredItems: [(ActionItem, Meeting)] {
        cachedActionItems.filter { item, meeting in
            if !showCompleted && item.isCompleted { return false }
            if priorityFilter == "urgent" && !item.isUrgent { return false }
            if priorityFilter != "all" && priorityFilter != "urgent" && item.priority != priorityFilter { return false }
            if showMyItemsOnly {
                let displayName = settings.displayName
                let assigneeIsMe = item.assignee?.localizedStandardContains(displayName) ?? false
                let assigneeIsEmpty = item.assignee?.trimmingCharacters(in: .whitespaces).isEmpty ?? true
                if !assigneeIsMe && !assigneeIsEmpty { return false }
            }
            if !filterText.isEmpty {
                let titleMatch = item.title.localizedStandardContains(filterText)
                let personMatch = item.assignee?.localizedStandardContains(filterText) ?? false
                let meetingMatch = meeting.title.localizedStandardContains(filterText)
                let attendeeMatch = meeting.calendarAttendees?.contains(where: {
                    $0.localizedStandardContains(filterText)
                }) ?? false
                if !titleMatch && !personMatch && !meetingMatch && !attendeeMatch { return false }
            }
            return true
        }
        .sorted { a, b in
            if a.0.priorityLevel != b.0.priorityLevel { return a.0.priorityLevel > b.0.priorityLevel }
            if a.0.isUrgent != b.0.isUrgent { return a.0.isUrgent }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Scope", selection: $showMyItemsOnly) {
                    Text("My Items").tag(true)
                    Text("All").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                TextField("Filter...", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Toggle("Show completed", isOn: $showCompleted)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Picker("Priority", selection: $priorityFilter) {
                    Text("All").tag("all")
                    Text("Urgent+").tag("urgent")
                    Divider()
                    Text("Critical").tag("critical")
                    Text("High").tag("high")
                    Text("Medium").tag("medium")
                    Text("Low").tag("low")
                }
                .frame(width: 110)

                Spacer()

                Button(isSyncingToNotion ? "Sending..." : "Send Visible to Notion") {
                    Task { await syncVisibleItemsToNotion() }
                }
                .buttonStyle(.glass)
                .disabled(isSyncingToNotion || filteredItems.isEmpty)

                Button(isDispatching ? "Sending..." : "Send All Confirmed") {
                    Task { await dispatchConfirmedItems() }
                }
                .buttonStyle(.glass)
                .disabled(isDispatching || confirmedItems.isEmpty)

                Text("\(filteredItems.filter { !$0.0.isCompleted }.count) open")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            List {
                ForEach(filteredItems, id: \.0.id) { item, meeting in
                    EditableActionItemRow(
                        item: item,
                        meetingTitle: meeting.title,
                        onSelectMeeting: {
                            selectedMeeting = meeting
                        },
                        onDelete: {
                            deleteActionItem(item, from: meeting)
                        }
                    )
                    .background {
                        if hoveredItemID == item.id {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.clear)
                                .glassEffect(.regular, in: .rect(cornerRadius: 8))
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredItemID = hovering ? item.id : nil
                        }
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                        .font(.title3)

                    TextField("Add action item...", text: $newActionItemTitle)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .onSubmit {
                            addActionItem()
                        }
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if filteredItems.isEmpty && newActionItemTitle.isEmpty {
                    ContentUnavailableView(
                        "No Action Items",
                        systemImage: "checkmark.circle",
                        description: Text("Type below to add one, or record a meeting to extract them automatically")
                    )
                }
            }
        }
        .navigationTitle("Action Items")
        .onAppear { cachedActionItems = computeAllActionItems() }
        .onChange(of: meetings) { cachedActionItems = computeAllActionItems() }
        .alert(alertTitle, isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var confirmedItems: [(ActionItem, Meeting)] {
        filteredItems.filter { $0.0.confirmedDestination != nil && !$0.0.isCompleted }
    }

    private func addActionItem() {
        let trimmed = newActionItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Attach to most recent completed meeting, or create a standalone one
        let targetMeeting: Meeting
        if let recent = meetings.first(where: { $0.status == .complete }) {
            targetMeeting = recent
        } else {
            let standalone = Meeting(title: "Action Items", date: .now)
            standalone.status = .complete
            modelContext.insert(standalone)
            targetMeeting = standalone
        }

        let newItem = ActionItem(title: trimmed)
        newItem.meeting = targetMeeting
        targetMeeting.actionItems.append(newItem)
        try? modelContext.save()
        newActionItemTitle = ""
        cachedActionItems = computeAllActionItems()
    }

    private func deleteActionItem(_ item: ActionItem, from meeting: Meeting) {
        meeting.actionItems.removeAll { $0.id == item.id }
        modelContext.delete(item)
        try? modelContext.save()
        cachedActionItems = computeAllActionItems()
    }

    @MainActor
    private func dispatchConfirmedItems() async {
        isDispatching = true
        defer { isDispatching = false }

        var successCount = 0
        var failCount = 0
        for (item, meeting) in confirmedItems {
            guard let destination = item.confirmedDestination else { continue }
            do {
                try await ActionItemDispatcher.dispatch(
                    item: item,
                    meetingTitle: meeting.title,
                    destination: destination,
                    settings: settings,
                    eventKitManager: eventKitManager,
                    modelContext: modelContext
                )
                successCount += 1
            } catch {
                failCount += 1
            }
        }

        alertTitle = "Dispatch"
        if successCount > 0 || failCount > 0 {
            var msg = "Dispatched \(successCount) action items."
            if failCount > 0 { msg += " \(failCount) failed." }
            alertMessage = msg
        }
    }

    private func computeAllActionItems() -> [(ActionItem, Meeting)] {
        meetings
            .filter { $0.status == .complete }
            .flatMap { meeting in
                meeting.actionItems.map { ($0, meeting) }
            }
    }

    @MainActor
    private func syncVisibleItemsToNotion() async {
        isSyncingToNotion = true
        defer { isSyncingToNotion = false }

        do {
            let result = try await ActionItemNotionSyncService.sync(
                targets: filteredItems.map {
                    ActionItemNotionSyncService.SyncTarget(
                        item: $0.0,
                        meetingTitle: $0.1.title.isEmpty ? "Untitled" : $0.1.title
                    )
                },
                settings: settings,
                modelContext: modelContext
            )
            alertTitle = "Notion Export"
            alertMessage = result.updatedCount > 0
                ? "Synced \(result.syncedCount) action items to Notion (\(result.createdCount) created, \(result.updatedCount) updated)."
                : "Sent \(result.syncedCount) action items to Notion."
        } catch {
            alertTitle = "Notion Export"
            alertMessage = error.localizedDescription
        }
    }
}
