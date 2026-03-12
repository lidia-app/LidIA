import SwiftUI

struct SearchResultsView: View {
    let queryService: MeetingQueryService
    let onSelectMeeting: (Meeting) -> Void

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            if queryService.isQuerying {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking...")
                        .foregroundStyle(.secondary)
                }
            } else if let error = queryService.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let response = queryService.lastResponse {
                // Answer
                Text(response.answer)
                    .font(.body)
                    .textSelection(.enabled)

                // Source meetings
                if !response.sourceMeetings.isEmpty {
                    Divider()
                    Text("Referenced Meetings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(response.sourceMeetings) { meeting in
                        Button {
                            onSelectMeeting(meeting)
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text(meeting.title)
                                Spacer()
                                Text(meeting.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        }
        .frame(maxWidth: 600, maxHeight: 400, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .shadow(radius: 8)
    }
}
