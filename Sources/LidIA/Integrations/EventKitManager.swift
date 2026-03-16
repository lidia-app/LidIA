import EventKit
import SwiftUI
import SwiftData
import UserNotifications
import os

@MainActor
@Observable
final class EventKitManager {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "EventKitManager")

    // MARK: - Calendar

    struct CalendarEvent: Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let attendees: [String]
        let calendarName: String
        let meetingLink: URL?
    }

    var upcomingEvents: [CalendarEvent] = []
    var todayEvents: [CalendarEvent] { upcomingEvents }
    var calendarAccessGranted = false
    var remindersAccessGranted = false
    var error: String?
    var backgroundContext: ModelContext?

    private let store = EKEventStore()
    private var pollTask: Task<Void, Never>?

    // MARK: - Calendar Access

    func requestCalendarAccess() async {
        do {
            calendarAccessGranted = try await store.requestFullAccessToEvents()
        } catch {
            self.error = "Calendar access denied: \(error.localizedDescription)"
        }
    }

    func startPolling(settings: AppSettings) {
        stopPolling()
        guard settings.calendarEnabled else { return }

        pollTask = Task {
            if !calendarAccessGranted {
                await requestCalendarAccess()
            }
            guard calendarAccessGranted else { return }

            while !Task.isCancelled {
                await refresh(settings: settings)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh(settings: AppSettings) async {
        error = nil
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 24 * 60 * 60)

        let predicate = store.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        upcomingEvents = ekEvents
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    attendees: event.attendees?.compactMap(\.name) ?? [],
                    calendarName: event.calendar?.title ?? "",
                    meetingLink: Self.extractMeetingLink(from: event)
                )
            }

        if settings.notifyUpcomingMeetings || settings.calendarRecordPromptEnabled || settings.prepNotificationsEnabled {
            scheduleNotifications(for: upcomingEvents, settings: settings)
        }
    }

    // MARK: - Reminders

    func requestRemindersAccess() async {
        do {
            remindersAccessGranted = try await store.requestFullAccessToReminders()
        } catch {
            self.error = "Reminders access denied: \(error.localizedDescription)"
        }
    }

    /// Finds or creates the "LidIA" reminders list.
    private func lidiaRemindersList() -> EKCalendar? {
        // Look for existing
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == "LidIA" }) {
            return existing
        }
        // Create new
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "LidIA"
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            Self.logger.error("Failed to create LidIA reminders list: \(error.localizedDescription)")
            return nil
        }
    }

    /// Creates or updates an EKReminder for an action item. Returns the reminder identifier.
    func syncReminder(
        reminderID: String?,
        title: String,
        deadlineText: String?,
        deadlineDate: Date?,
        isCompleted: Bool
    ) async -> String? {
        if !remindersAccessGranted {
            await requestRemindersAccess()
        }
        guard remindersAccessGranted else { return nil }
        guard let calendar = lidiaRemindersList() else { return nil }

        let reminder: EKReminder
        if let reminderID,
           let existingReminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder {
            reminder = existingReminder
        } else {
            reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
        }

        reminder.title = title
        reminder.calendar = calendar
        reminder.isCompleted = isCompleted
        reminder.dueDateComponents = deadlineDate.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        if deadlineDate == nil,
           let deadlineText,
           !deadlineText.isEmpty {
            reminder.notes = "Due: \(deadlineText)"
        } else {
            reminder.notes = nil
        }

        do {
            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            Self.logger.error("Failed to create reminder: \(error.localizedDescription)")
            return nil
        }
    }

    /// Creates an EKReminder for an action item. Returns the reminder identifier.
    func createReminder(title: String, deadline: String?) async -> String? {
        await syncReminder(
            reminderID: nil,
            title: title,
            deadlineText: deadline,
            deadlineDate: nil,
            isCompleted: false
        )
    }

    /// Updates an EKReminder's completion status.
    func updateReminderCompletion(reminderID: String, isCompleted: Bool) {
        guard let item = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        item.isCompleted = isCompleted
        try? store.save(item, commit: true)
    }

    /// Syncs completion status FROM Reminders back to the app.
    /// Returns a dictionary of reminderID → isCompleted.
    func syncReminderStatuses(reminderIDs: [String]) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for id in reminderIDs {
            if let item = store.calendarItem(withIdentifier: id) as? EKReminder {
                result[id] = item.isCompleted
            }
        }
        return result
    }

    // MARK: - Notifications

    private static var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestNotificationPermission() {
        guard canUseNotifications else {
            Self.logger.warning("Notifications unavailable — no bundle identifier (running outside .app bundle)")
            return
        }
        let logger = Logger(subsystem: "io.lidia.app", category: "EventKitManager")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                logger.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    static func registerNotificationCategories() {
        guard canUseNotifications else { return }

        let joinAndRecord = UNNotificationAction(
            identifier: "JOIN_AND_RECORD",
            title: "Join & Record",
            options: [.foreground]
        )
        let record = UNNotificationAction(
            identifier: "RECORD_MEETING",
            title: "Record",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )

        let preMeeting = UNNotificationCategory(
            identifier: "MEETING_PRE",
            actions: [joinAndRecord, dismiss],
            intentIdentifiers: []
        )
        let atMeeting = UNNotificationCategory(
            identifier: "MEETING_AT_TIME",
            actions: [record, dismiss],
            intentIdentifiers: []
        )

        let categories = Set([preMeeting, atMeeting])
            .union(NotificationDispatcher.notificationCategories())
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    private func scheduleNotifications(for events: [CalendarEvent], settings: AppSettings) {
        guard Self.canUseNotifications else { return }

        for event in events {
            let prepSummary = settings.prepNotificationsEnabled
                ? prepareSummary(for: event)
                : nil

            Self.scheduleEventNotifications(
                eventID: event.id,
                title: event.title,
                start: event.start,
                meetingLink: event.meetingLink,
                minutesBefore: settings.notifyUpcomingMeetings ? [settings.meetingNotificationMinutes, 1] : [],
                includeRecordPrompt: settings.calendarRecordPromptEnabled,
                prepSummary: prepSummary
            )
        }
    }

    /// Shared notification scheduler that works for any calendar source (Apple, Google, etc.)
    /// Sends exactly 2 notifications per event:
    /// 1. 5 minutes before — "Join & Record" action
    /// 2. At meeting time — "Record" prompt (suppressed if already recording)
    static func scheduleEventNotifications(
        eventID: String,
        title: String,
        start: Date,
        meetingLink: URL?,
        minutesBefore: [Int] = [],
        includeRecordPrompt: Bool = true,
        prepSummary: String? = nil
    ) {
        guard canUseNotifications else { return }

        let center = UNUserNotificationCenter.current()
        let now = Date()
        let linkString = meetingLink?.absoluteString ?? ""

        // 1) 5 minutes before — "Meeting Soon" with Join & Record
        let preDate = start.addingTimeInterval(-5 * 60)
        if preDate.timeIntervalSince(now) > 0 {
            let content = UNMutableNotificationContent()
            content.title = "Meeting Soon"
            content.body = "\(title) starts in 5 minutes"
            content.sound = .default
            content.categoryIdentifier = "MEETING_PRE"
            content.userInfo = [
                "eventID": eventID,
                "eventTitle": title,
                "meetingLink": linkString,
                "notificationType": "preMeeting"
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: preDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "lidia.pre.\(eventID)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }

        // 2) At meeting time — "Record [title]?" prompt
        if start.timeIntervalSince(now) > 0 {
            let content = UNMutableNotificationContent()
            content.title = "Record \(title)?"
            content.body = "Your meeting is starting now"
            content.sound = .default
            content.categoryIdentifier = "MEETING_AT_TIME"
            content.userInfo = [
                "eventID": eventID,
                "eventTitle": title,
                "meetingLink": linkString,
                "notificationType": "recordPrompt"
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: start
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "lidia.record.\(eventID)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func prepareSummary(for event: CalendarEvent) -> String? {
        guard !event.attendees.isEmpty, let context = backgroundContext else { return nil }
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let meetings = try? context.fetch(descriptor) else { return nil }
        let completed = meetings.filter { $0.status == .complete }
        guard !completed.isEmpty else { return nil }
        return MeetingContextRetrievalService.buildPrepSummary(attendees: event.attendees, meetings: completed)
    }

    // MARK: - Meeting Link Extraction

    private static let meetingLinkPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com)[^\s]*"#,
        options: .caseInsensitive
    )

    private static func extractMeetingLink(from event: EKEvent) -> URL? {
        if let url = event.url, isMeetingURL(url) {
            return url
        }
        // Scan notes and location for meeting URLs
        for text in [event.notes, event.location].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingLinkPattern.firstMatch(in: text, range: range),
               let matchRange = Range(match.range, in: text) {
                return URL(string: String(text[matchRange]))
            }
        }
        return nil
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("zoom.us") || host.contains("meet.google.com") || host.contains("teams.microsoft.com")
    }
}
