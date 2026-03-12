import Foundation
import Observation

@MainActor
@Observable
final class CalendarSettings {
    private var isLoading = false

    // Google Calendar
    var googleCalendarEnabled: Bool = false {
        didSet { saveDefault(googleCalendarEnabled, forKey: "googleCalendarEnabled") }
    }
    var googleClientID: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.google.clientID", value: googleClientID) }
    }
    var googleClientSecret: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.google.clientSecret", value: googleClientSecret) }
    }

    // Apple Calendar & Reminders (EventKit)
    var calendarEnabled: Bool = false {
        didSet { saveDefault(calendarEnabled, forKey: "calendarEnabled") }
    }
    var remindersEnabled: Bool = false {
        didSet { saveDefault(remindersEnabled, forKey: "remindersEnabled") }
    }
    var showCalendarSection: Bool = true {
        didSet { saveDefault(showCalendarSection, forKey: "showCalendarSection") }
    }
    var notifyUpcomingMeetings: Bool = false {
        didSet { saveDefault(notifyUpcomingMeetings, forKey: "notifyUpcomingMeetings") }
    }
    var calendarRecordPromptEnabled: Bool = true {
        didSet { saveDefault(calendarRecordPromptEnabled, forKey: "calendarRecordPromptEnabled") }
    }
    var prepNotificationsEnabled: Bool = true {
        didSet { saveDefault(prepNotificationsEnabled, forKey: "prepNotificationsEnabled") }
    }
    var meetingNotificationMinutes: Int = 5 {
        didSet { saveDefault(meetingNotificationMinutes, forKey: "meetingNotificationMinutes") }
    }

    // Proactive Assistant
    var proactiveMorningDigest: Bool = false {
        didSet { saveDefault(proactiveMorningDigest, forKey: "proactiveMorningDigest") }
    }
    var proactiveMorningDigestTime: Date = CalendarSettings.defaultTime(hour: 8, minute: 30) {
        didSet { saveDefault(proactiveMorningDigestTime, forKey: "proactiveMorningDigestTime") }
    }
    var proactiveMorningDigestFrequency: String = "daily" {
        didSet { saveDefault(proactiveMorningDigestFrequency, forKey: "proactiveMorningDigestFrequency") }
    }
    var proactivePreMeetingPrep: Bool = false {
        didSet { saveDefault(proactivePreMeetingPrep, forKey: "proactivePreMeetingPrep") }
    }
    var proactivePreMeetingMinutes: Int = 10 {
        didSet { saveDefault(proactivePreMeetingMinutes, forKey: "proactivePreMeetingMinutes") }
    }
    var proactivePostMeetingNudge: Bool = false {
        didSet { saveDefault(proactivePostMeetingNudge, forKey: "proactivePostMeetingNudge") }
    }
    var proactivePostMeetingMinutes: Int = 15 {
        didSet { saveDefault(proactivePostMeetingMinutes, forKey: "proactivePostMeetingMinutes") }
    }
    var proactiveActionItemReminders: Bool = false {
        didSet { saveDefault(proactiveActionItemReminders, forKey: "proactiveActionItemReminders") }
    }
    var proactiveQuietStart: Date = CalendarSettings.defaultTime(hour: 22, minute: 0) {
        didSet { saveDefault(proactiveQuietStart, forKey: "proactiveQuietStart") }
    }
    var proactiveQuietEnd: Date = CalendarSettings.defaultTime(hour: 7, minute: 0) {
        didSet { saveDefault(proactiveQuietEnd, forKey: "proactiveQuietEnd") }
    }

    // Meeting Detection
    var autoDetectMeetings: Bool = true {
        didSet { saveDefault(autoDetectMeetings, forKey: "autoDetectMeetings") }
    }

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }
        let defaults = UserDefaults.standard
        googleCalendarEnabled = defaults.bool(forKey: "googleCalendarEnabled")
        googleClientID = SettingsKeychain.load(key: "lidia.google.clientID") ?? ""
        googleClientSecret = SettingsKeychain.load(key: "lidia.google.clientSecret") ?? ""
        calendarEnabled = defaults.bool(forKey: "calendarEnabled")
        remindersEnabled = defaults.bool(forKey: "remindersEnabled")
        if let show = defaults.object(forKey: "showCalendarSection") as? Bool {
            showCalendarSection = show
        }
        notifyUpcomingMeetings = defaults.bool(forKey: "notifyUpcomingMeetings")
        if let promptEnabled = defaults.object(forKey: "calendarRecordPromptEnabled") as? Bool {
            calendarRecordPromptEnabled = promptEnabled
        }
        if let prepEnabled = defaults.object(forKey: "prepNotificationsEnabled") as? Bool {
            prepNotificationsEnabled = prepEnabled
        }
        if let minutes = defaults.object(forKey: "meetingNotificationMinutes") as? Int {
            meetingNotificationMinutes = minutes
        }
        if let val = defaults.object(forKey: "proactiveMorningDigest") as? Bool {
            proactiveMorningDigest = val
        }
        if let val = defaults.object(forKey: "proactiveMorningDigestTime") as? Date {
            proactiveMorningDigestTime = val
        }
        proactiveMorningDigestFrequency = defaults.string(forKey: "proactiveMorningDigestFrequency") ?? "daily"
        if let val = defaults.object(forKey: "proactivePreMeetingPrep") as? Bool {
            proactivePreMeetingPrep = val
        }
        if let val = defaults.object(forKey: "proactivePreMeetingMinutes") as? Int {
            proactivePreMeetingMinutes = val
        }
        if let val = defaults.object(forKey: "proactivePostMeetingNudge") as? Bool {
            proactivePostMeetingNudge = val
        }
        if let val = defaults.object(forKey: "proactivePostMeetingMinutes") as? Int {
            proactivePostMeetingMinutes = val
        }
        if let val = defaults.object(forKey: "proactiveActionItemReminders") as? Bool {
            proactiveActionItemReminders = val
        }
        if let val = defaults.object(forKey: "proactiveQuietStart") as? Date {
            proactiveQuietStart = val
        }
        if let val = defaults.object(forKey: "proactiveQuietEnd") as? Date {
            proactiveQuietEnd = val
        }
        if let val = defaults.object(forKey: "autoDetectMeetings") as? Bool {
            autoDetectMeetings = val
        }
    }

    // MARK: - Persistence Helpers

    private func saveDefault(_ value: some Any, forKey key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    static func defaultTime(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? .now
    }
}
