import SwiftUI
import SwiftData
import LidIAKit

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    NextMeetingView()
                } label: {
                    Label("Next Meeting", systemImage: "calendar")
                }

                NavigationLink {
                    ActionItemsView()
                } label: {
                    Label("Action Items", systemImage: "checklist")
                }

                NavigationLink {
                    QuickCaptureView()
                } label: {
                    Label("Quick Capture", systemImage: "mic.fill")
                }
            }
            .navigationTitle("LidIA")
        }
    }
}
