import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var relationshipStore = RelationshipStore()
    @State private var profiles: [RelationshipStore.PersonProfile] = []
    @State private var hoveredPersonID: String?
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
    }

    private func toggleFavorite(_ id: String) {
        if settings.favoritePersonIDs.contains(id) {
            settings.favoritePersonIDs.remove(id)
        } else {
            settings.favoritePersonIDs.insert(id)
        }
    }
}
