import SwiftUI
import SwiftData

struct SearchTabView: View {
    @Query(sort: \Meeting.date, order: .reverse) private var allMeetings: [Meeting]
    @Environment(\.modelContext) private var modelContext
    @Environment(MeetingQueryService.self) private var queryService
    @Environment(AppSettings.self) private var settings

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var onSelectMeeting: ((Meeting) -> Void)?

    private var filteredMeetings: [Meeting] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return Array(allMeetings.filter {
            $0.title.lowercased().contains(query) ||
            $0.summary.lowercased().contains(query)
        }.prefix(10))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Search meetings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($isSearchFocused)
                    .onSubmit { performAISearch() }
                if !searchText.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        searchText = ""
                        queryService.lastResponse = nil
                        queryService.error = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 8) {
                    if queryService.isQuerying {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Searching...").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    } else if let error = queryService.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    } else if let response = queryService.lastResponse {
                        SidebarSectionHeader("AI Answer")
                        Text(response.answer)
                            .font(.caption).textSelection(.enabled)
                            .padding(.horizontal, 12)

                        if !response.sourceMeetings.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(response.sourceMeetings) { meeting in
                                    SidebarRow(action: { onSelectMeeting?(meeting) }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.text").font(.caption2)
                                            Text(meeting.title).font(.subheadline).lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }

                    if !filteredMeetings.isEmpty {
                        SidebarSectionHeader("Meetings")
                        VStack(spacing: 2) {
                            ForEach(filteredMeetings) { meeting in
                                SidebarRow(action: { onSelectMeeting?(meeting) }) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                                            .font(.subheadline).lineLimit(1)
                                        Text(meeting.date, style: .date)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    if filteredMeetings.isEmpty && queryService.lastResponse == nil && !queryService.isQuerying && !searchText.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2).foregroundStyle(.quaternary)
                            Text("No results").font(.caption).foregroundStyle(.tertiary)
                            Text("Press Return for AI search").font(.caption2).foregroundStyle(.quaternary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { isSearchFocused = true }
    }

    private func performAISearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await queryService.query(trimmed, modelContext: modelContext, settings: settings)
        }
    }
}
