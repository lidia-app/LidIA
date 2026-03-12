import SwiftUI
import SwiftData
import LidIAKit

struct MeetingDetailiOSView: View {
    let meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                Text("Summary").tag(0)
                Text("Actions").tag(1)
                Text("Transcript").tag(2)
                Text("Notes").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: summaryContent
                    case 1: actionItemsContent
                    case 2: transcriptContent
                    case 3: notesContent
                    default: EmptyView()
                    }
                }
                .padding()
            }
        }
        .navigationTitle(meeting.title.isEmpty ? "Meeting" : meeting.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    @ViewBuilder
    private var summaryContent: some View {
        if meeting.summary.isEmpty && (meeting.userEditedSummary ?? "").isEmpty {
            ContentUnavailableView {
                Label("No Summary", systemImage: "doc.text")
            } description: {
                Text("This meeting hasn't been summarized yet.")
            }
        } else {
            Text(meeting.userEditedSummary ?? meeting.summary)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    // MARK: - Action Items

    @ViewBuilder
    private var actionItemsContent: some View {
        if meeting.actionItems.isEmpty {
            ContentUnavailableView {
                Label("No Action Items", systemImage: "checklist")
            } description: {
                Text("No action items were captured from this meeting.")
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(meeting.actionItems) { item in
                    HStack(alignment: .top) {
                        Button {
                            item.isCompleted.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? .green : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline)
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)

                            HStack(spacing: 6) {
                                if let assignee = item.assignee {
                                    Label(assignee, systemImage: "person")
                                }
                                if let deadline = item.displayDeadline {
                                    Label(deadline, systemImage: "calendar")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptContent: some View {
        let text = meeting.userEditedTranscript ?? meeting.refinedTranscript
        if text.isEmpty {
            ContentUnavailableView {
                Label("No Transcript", systemImage: "text.quote")
            } description: {
                Text("This meeting doesn't have a transcript yet.")
            }
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesContent: some View {
        if meeting.notes.isEmpty {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("No notes were taken during this meeting.")
            }
        } else {
            Text(meeting.notes)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
