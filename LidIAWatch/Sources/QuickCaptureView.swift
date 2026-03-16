import SwiftUI
import SwiftData
import LidIAKit

struct QuickCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var capturedText = ""
    @State private var saveAs: SaveType = .actionItem

    enum SaveType: String, CaseIterable {
        case actionItem = "Action Item"
        case note = "Note"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Dictation button — watchOS provides built-in dictation via TextField
            TextField("Dictate...", text: $capturedText)
                .font(.caption)

            Picker("Save as", selection: $saveAs) {
                ForEach(SaveType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.wheel)

            Button("Save") {
                save()
                dismiss()
            }
            .disabled(capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .navigationTitle("Capture")
    }

    private func save() {
        let text = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch saveAs {
        case .actionItem:
            let item = ActionItem(title: text)
            modelContext.insert(item)
        case .note:
            let meeting = Meeting(title: "Voice Note", date: .now, summary: text, status: .complete)
            meeting.notes = text
            modelContext.insert(meeting)
        }
        try? modelContext.save()
    }
}
