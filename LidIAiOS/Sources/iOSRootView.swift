import SwiftUI
import SwiftData
import LidIAKit

struct iOSRootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    DashboardView()
                }
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                NavigationStack {
                    iOSChatView()
                }
            }
            Tab("Action Items", systemImage: "checklist") {
                NavigationStack {
                    iOSActionItemsView()
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    iOSSettingsView()
                }
            }
        }
    }
}

// MARK: - Action Items (iOS)

struct iOSActionItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActionItem.deadlineDate) private var allActionItems: [ActionItem]
    @State private var filterText = ""
    @State private var showCompleted = false

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
                    description: Text("Action items from your meetings will appear here")
                )
            } else {
                ForEach(filteredItems) { item in
                    HStack {
                        Button {
                            item.isCompleted.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline)
                                .strikethrough(item.isCompleted)
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
                    }
                }
            }
        }
        .searchable(text: $filterText, prompt: "Filter...")
        .navigationTitle("Action Items")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("Completed", isOn: $showCompleted)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    private func isOverdue(_ item: ActionItem) -> Bool {
        guard let date = item.deadlineDate else { return false }
        return date < .now && !item.isCompleted
    }
}

