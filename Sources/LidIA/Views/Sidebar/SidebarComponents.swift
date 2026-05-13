import SwiftUI

// MARK: - Event Row with Join on Hover

/// Calendar event row with "Join" button appearing on hover.
struct EventRow: View {
    let event: GoogleCalendarClient.CalendarEvent
    var onSelect: () -> Void
    var onJoin: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.fromHex(event.colorHex) ?? .orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(event.start, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: isHovered ? 44 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if isHovered {
                Button("Join") { onJoin() }
                    .font(.caption2.weight(.medium))
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.trailing, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
                .opacity(isHovered ? 1 : 0)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
