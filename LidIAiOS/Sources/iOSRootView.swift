import SwiftUI
import SwiftData
import LidIAKit

private struct TabBarMinimizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

struct iOSRootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeTab()
                }
            }
            Tab("Action Items", systemImage: "checklist") {
                NavigationStack {
                    ActionItemsTab()
                }
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                NavigationStack {
                    ChatTab()
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsTab()
                }
            }
        }
        .modifier(TabBarMinimizeModifier())
    }
}
