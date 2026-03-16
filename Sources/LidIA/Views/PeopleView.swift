import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var relationshipStore = RelationshipStore()
    @State private var profiles: [RelationshipStore.PersonProfile] = []
    @State private var companies: [Company] = []
    @State private var hoveredPersonID: String?
    @State private var showCompanies = true
    @Binding var selectedMeeting: Meeting?

    private var favoriteProfiles: [RelationshipStore.PersonProfile] {
        profiles.filter { settings.favoritePersonIDs.contains($0.id) }
    }

    private var everyoneProfiles: [RelationshipStore.PersonProfile] {
        profiles.filter { !settings.favoritePersonIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No People Yet",
                    systemImage: "person.2",
                    description: Text("People will appear here after meetings with calendar attendees")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !companies.isEmpty {
                        Section("Companies") {
                            ForEach(companies) { company in
                                DisclosureGroup {
                                    ForEach(companyAttendeeProfiles(for: company), id: \.id) { profile in
                                        NavigationLink(value: profile.id) {
                                            PersonRow(profile: profile, isFavorite: settings.favoritePersonIDs.contains(profile.id)) {
                                                toggleFavorite(profile.id)
                                            }
                                        }
                                    }
                                    if companyAttendeeProfiles(for: company).isEmpty {
                                        Text("No profiles found for this company")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } label: {
                                    CompanyRow(company: company)
                                }
                            }
                        }
                    }

                    if !favoriteProfiles.isEmpty {
                        Section("Favorites") {
                            ForEach(favoriteProfiles) { profile in
                                NavigationLink(value: profile.id) {
                                    PersonRow(profile: profile, isFavorite: true) {
                                        toggleFavorite(profile.id)
                                    }
                                }
                                .background {
                                    if hoveredPersonID == profile.id {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.clear)
                                            .glassEffect(.regular, in: .rect(cornerRadius: 8))
                                    }
                                }
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        hoveredPersonID = hovering ? profile.id : nil
                                    }
                                }
                            }
                        }
                    }

                    Section("Everyone") {
                        ForEach(everyoneProfiles) { profile in
                            NavigationLink(value: profile.id) {
                                PersonRow(profile: profile, isFavorite: false) {
                                    toggleFavorite(profile.id)
                                }
                            }
                            .background {
                                if hoveredPersonID == profile.id {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.clear)
                                        .glassEffect(.regular, in: .rect(cornerRadius: 8))
                                }
                            }
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hoveredPersonID = hovering ? profile.id : nil
                                }
                            }
                        }
                    }
                }
                .navigationDestination(for: String.self) { profileID in
                    if let profile = profiles.first(where: { $0.id == profileID }) {
                        PersonDetailView(
                            profile: profile,
                            selectedMeeting: $selectedMeeting
                        )
                    }
                }
            }
        }
        .onAppear { refresh() }
        .navigationTitle("People")
    }

    private func refresh() {
        let userName = settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        profiles = relationshipStore.buildProfiles(modelContext: modelContext)
            .filter { userName.isEmpty || !$0.id.contains(userName) }

        // Build companies from all meetings
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allMeetings = (try? modelContext.fetch(descriptor)) ?? []
        companies = relationshipStore.companies(from: allMeetings)
    }

    private func companyAttendeeProfiles(for company: Company) -> [RelationshipStore.PersonProfile] {
        profiles.filter { profile in
            if let email = profile.email {
                return company.attendeeEmails.contains(email)
            }
            return false
        }
    }

    private func toggleFavorite(_ id: String) {
        if settings.favoritePersonIDs.contains(id) {
            settings.favoritePersonIDs.remove(id)
        } else {
            settings.favoritePersonIDs.insert(id)
        }
    }
}

// MARK: - Company Row

private struct CompanyRow: View {
    let company: Company

    var body: some View {
        HStack {
            Image(systemName: "building.2")
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(company.name)
                    .font(.subheadline.bold())
                Text(company.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("\(company.meetingCount) meeting\(company.meetingCount == 1 ? "" : "s")")
                    Text("\(company.attendeeEmails.count) attendee\(company.attendeeEmails.count == 1 ? "" : "s")")
                    if let lastDate = company.lastMeetingDate {
                        Text("Last: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if company.openActionItems > 0 {
                Text("\(company.openActionItems)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }
}
