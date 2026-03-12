import SwiftUI
import SwiftData

struct PersonDetailView: View {
    let profile: RelationshipStore.PersonProfile
    @Binding var selectedMeeting: Meeting?
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var newTalkingPoint = ""

    private var isFavorite: Bool {
        settings.favoritePersonIDs.contains(profile.id)
    }

    private var overdueItems: [ActionItem] {
        profile.openActionItems.filter { item in
            guard let meeting = item.meeting else { return false }
            return (Calendar.current.dateComponents([.day], from: meeting.date, to: .now).day ?? 0) > 7
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    AvatarView(name: profile.name, size: 48)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(profile.name)
                                .font(.title2.bold())
                            Button(isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: isFavorite ? "star.fill" : "star") {
                                if isFavorite {
                                    settings.favoritePersonIDs.remove(profile.id)
                                } else {
                                    settings.favoritePersonIDs.insert(profile.id)
                                }
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(isFavorite ? .yellow : .secondary)
                            .buttonStyle(.borderless)
                        }
                        if let email = profile.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(profile.meetingCount) meetings · Last met \(profile.lastMet.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(relationshipStatusLine(
                            daysSinceLastMet: Calendar.current.dateComponents([.day], from: profile.lastMet, to: .now).day ?? 0,
                            overdueCount: overdueItems.count,
                            totalOpen: profile.openActionItems.count
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Overdue commitments
                if !overdueItems.isEmpty {
                    Section("Overdue Commitments") {
                        ForEach(overdueItems, id: \.id) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline)
                                    if let meeting = item.meeting {
                                        Text("From \(meeting.title) on \(meeting.date.formatted(date: .abbreviated, time: .omitted)) — still open")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Open action items (excluding those already shown as overdue)
                let nonOverdueItems = profile.openActionItems.filter { item in
                    !overdueItems.contains(where: { $0.id == item.id })
                }
                if !nonOverdueItems.isEmpty {
                    Section("Open Action Items") {
                        ForEach(nonOverdueItems, id: \.id) { item in
                            HStack {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                                Text(item.title)
                                    .font(.subheadline)
                                if let assignee = item.assignee {
                                    Spacer()
                                    Text(assignee)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Talking points
                Section("Talking Points for Next Meeting") {
                    ForEach(profile.talkingPoints, id: \.id) { tp in
                        HStack {
                            Text("• \(tp.content)")
                                .font(.subheadline)
                            Spacer()
                            Button {
                                tp.isUsed = true
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack {
                        TextField("Add talking point...", text: $newTalkingPoint)
                            .textFieldStyle(.plain)
                            .onSubmit { addTalkingPoint() }
                        Button("Add") { addTalkingPoint() }
                            .disabled(newTalkingPoint.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // Meeting history
                Section("Meeting History") {
                    ForEach(profile.recentMeetings, id: \.id) { meeting in
                        Button {
                            selectedMeeting = meeting
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                                    .font(.subheadline.bold())
                                Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !meeting.summary.isEmpty {
                                    Text(meeting.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    private func relationshipStatusLine(daysSinceLastMet: Int, overdueCount: Int, totalOpen: Int) -> String {
        var parts: [String] = []
        if daysSinceLastMet == 0 { parts.append("Met today") }
        else if daysSinceLastMet == 1 { parts.append("Last met yesterday") }
        else { parts.append("Last met \(daysSinceLastMet) days ago") }

        parts.append("\(totalOpen) open items")

        if overdueCount > 0 {
            parts.append("\(overdueCount) overdue — Needs attention")
        } else {
            parts.append("All on track")
        }
        return parts.joined(separator: " · ")
    }

    private func addTalkingPoint() {
        let trimmed = newTalkingPoint.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tp = TalkingPoint(personIdentifier: profile.id, content: trimmed)
        modelContext.insert(tp)
        try? modelContext.save()
        newTalkingPoint = ""
    }
}
