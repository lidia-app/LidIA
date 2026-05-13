import SwiftUI

@MainActor
@Observable
final class NavigationState {
    enum SidebarTab: String, CaseIterable {
        case home, chat, meetings, search

        var icon: String {
            switch self {
            case .home: "house"
            case .chat: "bubble.left.and.bubble.right"
            case .meetings: "calendar"
            case .search: "magnifyingglass"
            }
        }

        var label: String {
            switch self {
            case .home: "Home"
            case .chat: "Chat"
            case .meetings: "Meetings"
            case .search: "Search"
            }
        }
    }

    enum DetailDestination {
        case meeting, calendarEvent, home, actionItems, people, chat
    }

    var selectedMeeting: Meeting?
    var selectedCalendarEvent: GoogleCalendarClient.CalendarEvent?
    var selectedFolder: String?
    var detailDestination: DetailDestination = .home
    var selectedTab = "summary"
    var detailPath = NavigationPath()
    var columnVisibility: NavigationSplitViewVisibility = .automatic
    var sidebarTab: SidebarTab = .home
    var searchFocusTrigger = false
}
