import SwiftUI

@MainActor
@Observable
final class NavigationState {
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
    var searchFocusTrigger = false
}
