import SwiftUI
import SwiftData
import LidIAKit

@main
struct LidIAWatchApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([Meeting.self, ActionItem.self, TalkingPoint.self])
        let config = ModelConfiguration(cloudKitDatabase: .none)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
