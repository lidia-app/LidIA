import SwiftUI
import SwiftData

// MARK: - Meeting List View

struct MeetingListView: View {
    @Query(filter: #Predicate<ActionItem> { !$0.isCompleted }) private var openActionItems: [ActionItem]
    @Query private var allMeetings: [Meeting]
    @Environment(\.modelContext) private var modelContext
    @Binding var searchFocusTrigger: Bool
    @Binding var selectedFolder: String?
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor
    @Environment(AppSettings.self) private var settings
    @Environment(MeetingQueryService.self) private var queryService
    var onOpenHome: (() -> Void)?
    var onOpenChat: (() -> Void)?
    var onOpenActionItems: (() -> Void)?
    var onOpenPeople: (() -> Void)?
    var onSelectMeeting: ((Meeting) -> Void)?
    /// Which workspace item is active ("home", "chat", "actionItems", "people"), nil when a meeting is selected.
    var activeWorkspaceItem: String?
    @State private var searchText = ""
    @State private var showAIResults = false
    @FocusState private var isSearchFocused: Bool

    /// All unique folder names from existing meetings.
    private var allFolders: [String] {
        Array(Set(allMeetings.compactMap(\.folder))).sorted()
    }

    @ViewBuilder
    private func workspaceRow(_ id: String, label: String, icon: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        let isActive = activeWorkspaceItem == id
        Button {
            action()
        } label: {
            HStack {
                Label(label, systemImage: icon)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular.tint(.orange), in: .capsule)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isActive
                ? AnyView(Capsule().fill(.clear).glassEffect(.regular.tint(.accentColor), in: .capsule))
                : nil
        )
    }

    // MARK: Body

    var body: some View {
        List {
            // Workspace destinations (top)
            Section("Workspace") {
                workspaceRow("home", label: "Home", icon: "house") {
                    onOpenHome?()
                }

                workspaceRow("chat", label: "Chat", icon: "bubble.left.and.bubble.right") {
                    onOpenChat?()
                }

                workspaceRow("actionItems", label: "Action Items", icon: "checklist", badge: openActionItems.count) {
                    onOpenActionItems?()
                }

                workspaceRow("people", label: "All People", icon: "person.2") {
                    onOpenPeople?()
                }
            }

            // Search + folder filters
            Section {
                // Search field — AI search on Enter
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Search meetings & people...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit {
                            performAISearch()
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            dismissAIResults()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))

                // AI search results (inline)
                if showAIResults {
                    if queryService.isQuerying {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if let error = queryService.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let response = queryService.lastResponse {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(response.answer)
                                .font(.caption)
                                .textSelection(.enabled)
                                .foregroundStyle(.primary)

                            if !response.sourceMeetings.isEmpty {
                                ForEach(response.sourceMeetings) { meeting in
                                    Button {
                                        onSelectMeeting?(meeting)
                                        dismissAIResults()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.text")
                                                .font(.caption2)
                                            Text(meeting.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(meeting.date, style: .date)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Folder filter
                if !allFolders.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button {
                                withAnimation { selectedFolder = nil }
                            } label: {
                                Label("All", systemImage: "folder")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.glass)
                            .opacity(selectedFolder == nil ? 1.0 : 0.5)

                            ForEach(allFolders, id: \.self) { folder in
                                Button {
                                    withAnimation { selectedFolder = folder }
                                } label: {
                                    Label(folder, systemImage: "folder.fill")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.glass)
                                .opacity(selectedFolder == folder ? 1.0 : 0.5)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Meetings")
        .onChange(of: searchFocusTrigger) {
            isSearchFocused = true
        }
    }

    // MARK: - Actions

    private func performAISearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showAIResults = true
        Task {
            await queryService.query(trimmed, modelContext: modelContext, settings: settings)
        }
    }

    private func dismissAIResults() {
        showAIResults = false
        queryService.lastResponse = nil
        queryService.error = nil
    }
}
