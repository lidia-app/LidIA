import SwiftUI

struct PersonRow: View {
    let profile: RelationshipStore.PersonProfile
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack {
            AvatarView(name: profile.name, size: 32)
            Circle()
                .fill(healthColor(for: profile))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.subheadline.bold())
                if let email = profile.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(profile.meetingCount) meetings · Last: \(profile.lastMet.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !profile.openActionItems.isEmpty {
                Text("\(profile.openActionItems.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2))
                    .clipShape(Capsule())
            }
            Button(isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: isFavorite ? "star.fill" : "star", action: onToggleFavorite)
                .foregroundStyle(isFavorite ? .yellow : .secondary)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    private func healthColor(for profile: RelationshipStore.PersonProfile) -> Color {
        let days = Calendar.current.dateComponents([.day], from: profile.lastMet, to: .now).day ?? 0
        let hasOverdue = profile.openActionItems.contains { item in
            guard let meeting = item.meeting else { return false }
            return (Calendar.current.dateComponents([.day], from: meeting.date, to: .now).day ?? 0) > 14
        }
        if hasOverdue { return .red }
        if days <= 7 { return .green }
        if days <= 21 { return .yellow }
        return .red
    }
}
