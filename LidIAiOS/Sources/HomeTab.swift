import SwiftUI
import SwiftData
import LidIAKit

struct HomeTab: View {
    @Query(sort: \Meeting.date, order: .forward) private var allMeetings: [Meeting]
    @Environment(\.modelContext) private var modelContext
    @State private var showVoiceNote = false

    private var upcomingMeetings: [Meeting] {
        allMeetings.filter { $0.date > .now && $0.status != .recording }
            .prefix(5).map { $0 }
    }

    private var recentMeetings: [Meeting] {
        allMeetings.filter { $0.date <= .now && $0.status != .recording }
            .sorted { $0.date > $1.date }
            .prefix(10).map { $0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Coming Up
                if !upcomingMeetings.isEmpty {
                    Section {
                        ForEach(upcomingMeetings) { meeting in
                            NavigationLink(value: meeting.id) {
                                MeetingCardView(meeting: meeting)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Coming Up")
                            .font(.title2.bold())
                            .padding(.horizontal, 4)
                    }
                }

                // Recent Meetings
                Section {
                    if recentMeetings.isEmpty {
                        ContentUnavailableView(
                            "No Meetings Yet",
                            systemImage: "waveform",
                            description: Text("Meetings recorded on your Mac will appear here after sync.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(recentMeetings) { meeting in
                            NavigationLink(value: meeting.id) {
                                MeetingCardView(meeting: meeting)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Recent Meetings")
                        .font(.title2.bold())
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
        .navigationTitle("LidIA")
        .navigationDestination(for: UUID.self) { meetingID in
            if let meeting = allMeetings.first(where: { $0.id == meetingID }) {
                MeetingDetailiOSView(meeting: meeting)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showVoiceNote = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glassProminent)
            .padding(24)
        }
        .sheet(isPresented: $showVoiceNote) {
            VoiceNoteSheet()
        }
    }
}
