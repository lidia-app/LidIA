import SwiftUI
import SwiftData
import LidIAKit

struct ActionItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ActionItem> { !$0.isCompleted },
           sort: \ActionItem.deadlineDate)
    private var openItems: [ActionItem]

    var body: some View {
        List {
            if openItems.isEmpty {
                Text("All clear!")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openItems) { item in
                    Button {
                        item.isCompleted = true
                        try? modelContext.save()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(3)
                            if let deadline = item.displayDeadline {
                                Text(deadline)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Action Items")
    }
}
