import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var sidebarTab: NavigationState.SidebarTab
    @Binding var selectedFolder: String?
    var onSelectMeeting: ((Meeting) -> Void)?
    var onSelectEvent: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onOpenActionItems: (() -> Void)?
    var onOpenPeople: (() -> Void)?
    var onRecord: ((GoogleCalendarClient.CalendarEvent) -> Void)?
    var onSelectMeetingByID: ((UUID) -> Void)?
    var onSelectThread: ((UUID) -> Void)?
    var activeThreadID: UUID?
    var onNewChat: (() -> Void)?
    var onNewNote: (() -> Void)?
    var onTabReclick: ((NavigationState.SidebarTab) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingBottomBar
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 6)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(NavigationState.SidebarTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tabButton(_ tab: NavigationState.SidebarTab) -> some View {
        let isActive = sidebarTab == tab
        Button {
            if isActive { onTabReclick?(tab) }
            else { withAnimation(.easeInOut(duration: 0.2)) { sidebarTab = tab } }
        } label: {
            Image(systemName: tab.icon)
                .font(.subheadline.weight(isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 30, height: 28)
                .background(isActive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(tab.label)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch sidebarTab {
        case .home:
            HomeTabView(
                onSelectMeeting: onSelectMeeting,
                onSelectEvent: onSelectEvent,
                onRecord: onRecord,
                onOpenActionItems: onOpenActionItems,
                onOpenPeople: onOpenPeople,
                onSelectMeetingByID: onSelectMeetingByID,
                onOpenMeetings: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sidebarTab = .meetings
                    }
                }
            )
        case .chat:
            ChatTabView(onSelectThread: onSelectThread, activeThreadID: activeThreadID)
        case .meetings:
            MeetingsTabView(
                selectedFolder: $selectedFolder,
                onSelectMeeting: onSelectMeeting,
                onSelectEvent: onSelectEvent
            )
        case .search:
            SearchTabView(onSelectMeeting: onSelectMeeting)
        }
    }

    // MARK: - Floating Bottom Bar

    private var floatingBottomBar: some View {
        HStack(spacing: 0) {
            Menu {
                Button {
                    onNewChat?()
                } label: {
                    Label("New Chat", systemImage: "sparkles")
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button {
                    onNewNote?()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 36, height: 36)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .help("Create…")

            Spacer(minLength: 0)
        }
    }
}
