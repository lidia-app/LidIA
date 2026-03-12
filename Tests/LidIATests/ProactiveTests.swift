import Foundation
import Testing
@testable import LidIA

@Test func quietHoursSuppressAcrossMidnight() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 23, minute: 15))!
    let quietStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 22, minute: 0))!
    let quietEnd = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 7, minute: 0))!

    #expect(ProactiveScheduler.isWithinQuietHours(now: now, quietStart: quietStart, quietEnd: quietEnd))
}

@Test func nextDailyDigestUsesSameDayWhenStillUpcoming() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 7, minute: 45))!
    let digestTime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 8, minute: 30))!

    let next = ProactiveScheduler.nextMorningDigestDate(
        after: now,
        triggerTime: digestTime,
        frequency: .daily,
        calendar: calendar
    )

    #expect(next == calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 8, minute: 30))!)
}

@Test func nextMondayDigestSkipsToNextWeekAfterMondayWindow() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 9, minute: 0))!
    let digestTime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8, minute: 30))!

    let next = ProactiveScheduler.nextMorningDigestDate(
        after: now,
        triggerTime: digestTime,
        frequency: .monday,
        calendar: calendar
    )

    #expect(next == calendar.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8, minute: 30))!)
}

@Test func notificationDispatcherDefinesExpectedCategoryIdentifiers() {
    #expect(NotificationDispatcher.categoryIdentifiers == [
        NotificationDispatcher.Category.morningDigest.rawValue,
        NotificationDispatcher.Category.preMeetingPrep.rawValue,
        NotificationDispatcher.Category.postMeetingNudge.rawValue,
        NotificationDispatcher.Category.actionItemReminder.rawValue,
    ])
}
