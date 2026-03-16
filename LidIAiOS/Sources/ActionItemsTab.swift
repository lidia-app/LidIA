import SwiftUI
import SwiftData
import LidIAKit

struct ActionItemsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActionItem.deadlineDate) private var allActionItems: [ActionItem]
    @State private var filterText = ""
    @State private var showCompleted = false
    @State private var editingItem: ActionItem?
    @State private var showNewItemSheet = false
    @State private var newItemTitle = ""

    private var filteredItems: [ActionItem] {
        allActionItems.filter { item in
            if !showCompleted && item.isCompleted { return false }
            if !filterText.isEmpty {
                let titleMatch = item.title.localizedCaseInsensitiveContains(filterText)
                let assigneeMatch = item.assignee?.localizedCaseInsensitiveContains(filterText) ?? false
                if !titleMatch && !assigneeMatch { return false }
            }
            return true
        }
    }

    var body: some View {
        List {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Action Items",
                    systemImage: "checkmark.circle",
                    description: Text("Action items from your meetings will appear here after sync.")
                )
            } else {
                ForEach(filteredItems) { item in
                    actionItemRow(item)
                        .swipeActions(edge: .leading) {
                            Button {
                                item.isCompleted.toggle()
                                try? modelContext.save()
                            } label: {
                                Label(item.isCompleted ? "Undo" : "Done", systemImage: item.isCompleted ? "arrow.uturn.left" : "checkmark")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(item)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            editingItem = item
                        }
                }
            }
        }
        .searchable(text: $filterText, prompt: "Filter action items...")
        .navigationTitle("Action Items")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show Completed", isOn: $showCompleted)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewItemSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingItem) { item in
            ActionItemEditView(item: item)
        }
        .alert("New Action Item", isPresented: $showNewItemSheet) {
            TextField("Title", text: $newItemTitle)
            Button("Cancel", role: .cancel) { newItemTitle = "" }
            Button("Add") {
                let trimmed = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let item = ActionItem(title: trimmed)
                modelContext.insert(item)
                try? modelContext.save()
                newItemTitle = ""
            }
        }
    }

    private func actionItemRow(_ item: ActionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                item.isCompleted.toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    if let assignee = item.assignee, !assignee.isEmpty {
                        Label(assignee, systemImage: "person")
                    }
                    if let deadline = item.displayDeadline {
                        Label(deadline, systemImage: "calendar")
                            .foregroundStyle(isOverdue(item) ? .red : .secondary)
                    }
                    if item.priority != "none" {
                        Text(item.priority.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(priorityColor(item.priority).opacity(0.15), in: Capsule())
                            .foregroundStyle(priorityColor(item.priority))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let meetingTitle = item.meeting?.title, !meetingTitle.isEmpty {
                    Text(meetingTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func isOverdue(_ item: ActionItem) -> Bool {
        guard let date = item.deadlineDate else { return false }
        return date < .now && !item.isCompleted
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "critical": .red
        case "high": .orange
        case "medium": .yellow
        case "low": .blue
        default: .secondary
        }
    }
}

// MARK: - Edit View

struct ActionItemEditView: View {
    @Bindable var item: ActionItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Action item", text: $item.title, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Details") {
                    TextField("Assignee", text: Binding(
                        get: { item.assignee ?? "" },
                        set: { item.assignee = $0.isEmpty ? nil : $0 }
                    ))

                    DatePicker("Deadline",
                        selection: Binding(
                            get: { item.deadlineDate ?? .now },
                            set: { item.deadlineDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    Picker("Priority", selection: $item.priority) {
                        Text("None").tag("none")
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Critical").tag("critical")
                    }
                }

                Section {
                    Toggle("Completed", isOn: $item.isCompleted)
                }
            }
            .navigationTitle("Edit Action Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
