import SwiftUI
import SwiftData

struct ChatTabView: View {
    @Query(sort: \ChatThreadModel.updatedAt, order: .reverse) private var threads: [ChatThreadModel]
    @Environment(\.modelContext) private var modelContext

    var onSelectThread: ((UUID) -> Void)?
    var activeThreadID: UUID?

    var body: some View {
        if threads.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
                Text("No chats yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(threads) { thread in
                        let isActive = thread.id == activeThreadID
                        SidebarRow(action: { onSelectThread?(thread.id) }) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(thread.title.isEmpty ? "New Chat" : thread.title)
                                    .font(.subheadline)
                                    .fontWeight(isActive ? .semibold : .regular)
                                    .lineLimit(1)
                                if let lastMessage = thread.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
                                    Text(lastMessage.content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text(thread.updatedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                modelContext.delete(thread)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }
}
