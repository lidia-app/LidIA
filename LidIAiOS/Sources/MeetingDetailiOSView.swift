import SwiftUI
import SwiftData
import LidIAKit

struct MeetingDetailiOSView: View {
    let meeting: Meeting
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = "summary"

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Summary").tag("summary")
                Text("Actions").tag("actions")
                Text("Transcript").tag("transcript")
                Text("Notes").tag("notes")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            tabContent
        }
        .navigationTitle(meeting.title.isEmpty ? "Meeting" : meeting.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "summary": summaryContent
        case "actions": actionsContent
        case "transcript": transcriptContent
        case "notes": notesContent
        default: EmptyView()
        }
    }

    // MARK: - Summary

    private var summaryContent: some View {
        ScrollView {
            let text = meeting.userEditedSummary ?? meeting.summary
            if text.isEmpty {
                ContentUnavailableView(
                    "No Summary",
                    systemImage: "doc.text",
                    description: Text("This meeting hasn't been summarized yet.")
                )
                .padding(.top, 60)
            } else {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    // MARK: - Action Items

    private var actionsContent: some View {
        List {
            if meeting.actionItems.isEmpty {
                ContentUnavailableView(
                    "No Action Items",
                    systemImage: "checklist",
                    description: Text("No action items were captured from this meeting.")
                )
            } else {
                ForEach(meeting.actionItems) { item in
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

                            HStack(spacing: 8) {
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
                    .swipeActions(edge: .leading) {
                        Button {
                            item.isCompleted.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(
                                item.isCompleted ? "Undo" : "Done",
                                systemImage: item.isCompleted ? "arrow.uturn.left" : "checkmark"
                            )
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            meeting.actionItems.removeAll { $0.id == item.id }
                            modelContext.delete(item)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Transcript

    private var transcriptContent: some View {
        ScrollView {
            let refined = meeting.userEditedTranscript ?? meeting.refinedTranscript
            if refined.isEmpty && meeting.rawTranscript.isEmpty {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "text.quote",
                    description: Text("This meeting doesn't have a transcript yet.")
                )
                .padding(.top, 60)
            } else if !meeting.rawTranscript.isEmpty {
                // Chat-bubble style transcript grouped by speaker
                transcriptBubbles
            } else {
                Text(refined)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var transcriptBubbles: some View {
        let segments = groupTranscriptBySegment(meeting.rawTranscript)
        LazyVStack(spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let isLocal = segment.isLocal
                HStack {
                    if isLocal { Spacer(minLength: 60) }
                    Text(segment.text)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isLocal ? Color.accentColor.opacity(0.2) : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .textSelection(.enabled)
                    if !isLocal { Spacer(minLength: 60) }
                }
            }
        }
        .padding()
    }

    // MARK: - Notes (editable)

    private var notesContent: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { meeting.notes },
                set: { newValue in
                    meeting.notes = newValue
                    try? modelContext.save()
                }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)

            if meeting.notes.isEmpty {
                Text("Write your notes...")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private struct TranscriptSegment {
        let isLocal: Bool
        let text: String
    }

    private func groupTranscriptBySegment(_ words: [TranscriptWord]) -> [TranscriptSegment] {
        guard !words.isEmpty else { return [] }
        var segments: [TranscriptSegment] = []
        var currentWords: [String] = []
        var currentIsLocal = words[0].isLocalSpeaker ?? false

        for word in words {
            let isLocal = word.isLocalSpeaker ?? false
            if isLocal != currentIsLocal {
                if !currentWords.isEmpty {
                    segments.append(TranscriptSegment(isLocal: currentIsLocal, text: currentWords.joined(separator: " ")))
                }
                currentWords = [word.word]
                currentIsLocal = isLocal
            } else {
                currentWords.append(word.word)
            }
        }
        if !currentWords.isEmpty {
            segments.append(TranscriptSegment(isLocal: currentIsLocal, text: currentWords.joined(separator: " ")))
        }
        return segments
    }
}
