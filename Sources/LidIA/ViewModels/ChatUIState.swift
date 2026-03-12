import SwiftUI

@MainActor
@Observable
final class ChatUIState {
    var chatFocusTrigger = false
    var chatPopupVisible = false
    var chatFullscreenThreadID: UUID?

    /// Persisted via UserDefaults (can't use @AppStorage inside @Observable)
    var quickChatVisible: Bool {
        didSet { UserDefaults.standard.set(quickChatVisible, forKey: "quickChat.visible") }
    }
    var quickChatExpanded: Bool {
        didSet { UserDefaults.standard.set(quickChatExpanded, forKey: "quickChat.expanded") }
    }

    init() {
        self.quickChatVisible = UserDefaults.standard.object(forKey: "quickChat.visible") as? Bool ?? true
        self.quickChatExpanded = UserDefaults.standard.object(forKey: "quickChat.expanded") as? Bool ?? false
    }
}
