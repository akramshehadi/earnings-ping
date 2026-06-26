import Foundation
import Testing
@testable import EarningsPing

// MARK: - Date helpers

/// NY-anchored day parser, matching how the app stores earnings dates.
private let nyDay = FinnhubProvider.dayFormatter

private func day(_ ymd: String) -> Date { nyDay.date(from: ymd)! }

private let newYork = Calendar(identifier: .gregorian, timeZone: "America/New_York")
private let pacific = TimeZone(identifier: "America/Los_Angeles")!
private let eastern = TimeZone(identifier: "America/New_York")!

private extension Calendar {
    init(identifier: Calendar.Identifier, timeZone id: String) {
        self.init(identifier: identifier)
        self.timeZone = TimeZone(identifier: id)!
    }
}

// MARK: - Trading calendar (pure)

@Suite("Trading calendar")
struct TradingCalendarTests {
    private let cal = TradingCalendar.nyse

    @Test func weekendsAreNotTradingDays() {
        #expect(cal.isTradingDay(day("2026-07-04")) == false) // Saturday
        #expect(cal.isTradingDay(day("2026-07-05")) == false) // Sunday
    }

    @Test func bundledHolidayIsNotATradingDay() {
        #expect(cal.isTradingDay(day("2026-07-03")) == false) // Independence (observed)
        #expect(cal.isTradingDay(day("2026-12-25")) == false) // Christmas
    }

    @Test func ordinaryWeekdayIsATradingDay() {
        #expect(cal.isTradingDay(day("2026-07-08")) == true) // Wednesday
    }

    /// Acceptance: a Monday event, one trading day before, lands on Friday.
    @Test func oneTradingDayBeforeMondaySkipsWeekend() {
        let monday = day("2026-07-13")
        #expect(cal.tradingDay(before: monday, count: 1) == day("2026-07-10")) // Friday
    }

    @Test func oneTradingDayBeforeSkipsAHoliday() {
        // Tue 2026-05-26 follows Memorial Day (Mon 2026-05-25, a holiday), so
        // one trading day back skips the holiday + weekend to the prior Friday.
        let tuesday = day("2026-05-26")
        #expect(cal.tradingDay(before: tuesday, count: 1) == day("2026-05-22"))
    }

    @Test func zeroTradingDaysIsTheSameDay() {
        #expect(cal.tradingDay(before: day("2026-07-13"), count: 0) == day("2026-07-13"))
    }
}

// MARK: - Notification factory (pure)

@Suite("Notification factory")
struct NotificationFactoryTests {
    private let calendar = TradingCalendar.nyse

    /// Acceptance: Monday-BMO, N=1 → reminder fires Friday morning, local time.
    @Test func reminderFiresFridayMorningForMondayEvent() throws {
        let monday = day("2026-07-13")
        let fire = try #require(NotificationFactory.reminderFireDate(
            eventDate: monday,
            leadTimeTradingDays: 1,
            tradingCalendar: calendar,
            localCalendar: newYork,
            now: day("2026-06-25")
        ))
        let parts = newYork.dateComponents([.year, .month, .day, .hour, .weekday], from: fire)
        #expect(parts.year == 2026 && parts.month == 7 && parts.day == 10) // Friday
        #expect(parts.weekday == 6)        // Friday
        #expect(parts.hour == NotificationFactory.morningHour)
    }

    @Test func reminderInThePastIsNotScheduled() {
        let fire = NotificationFactory.reminderFireDate(
            eventDate: day("2026-07-13"),
            leadTimeTradingDays: 1,
            tradingCalendar: calendar,
            localCalendar: newYork,
            now: day("2026-08-01") // event already past
        )
        #expect(fire == nil)
    }

    @Test func bmoCutoffConvertsToLocalTime() {
        let date = day("2026-07-13")
        #expect(NotificationFactory.localCutoffString(session: .bmo, eventDate: date, localTimeZone: eastern) == "9:30 AM")
        #expect(NotificationFactory.localCutoffString(session: .bmo, eventDate: date, localTimeZone: pacific) == "6:30 AM")
    }

    @Test func amcCutoffConvertsToLocalTime() {
        let date = day("2026-07-13")
        #expect(NotificationFactory.localCutoffString(session: .amc, eventDate: date, localTimeZone: eastern) == "4:00 PM")
        #expect(NotificationFactory.localCutoffString(session: .amc, eventDate: date, localTimeZone: pacific) == "1:00 PM")
    }

    @Test func unknownSessionHasNoCutoff() {
        #expect(NotificationFactory.localCutoffString(session: .unknown, eventDate: day("2026-07-13"), localTimeZone: eastern) == nil)
    }

    @Test func reminderBodyNamesSessionAndLocalCutoff() {
        let target = ReminderTarget(symbol: "AAPL", companyName: "Apple Inc", eventDate: day("2026-07-13"), session: .bmo)
        let note = NotificationFactory.reminder(for: target, fireDate: day("2026-07-10"), localTimeZone: pacific)
        #expect(note.id == "reminder-AAPL")
        #expect(note.title == "AAPL reports Mon, Jul 13")
        #expect(note.body == "Before market open — 6:30 AM your time")
    }

    @Test func dateChangeAlertNamesNewDateAndSession() {
        let change = DateChange(
            symbol: "AAPL",
            companyName: "Apple Inc",
            previousDate: day("2026-07-29"),
            newDate: day("2026-07-22"),
            newSession: .amc
        )
        let note = NotificationFactory.dateChange(change, localTimeZone: pacific)
        #expect(note.fireDate == nil)                      // delivered immediately
        #expect(note.title == "AAPL earnings moved")
        #expect(note.body == "Now Jul 22, AMC (was Jul 29)")
    }
}

// MARK: - Scheduler (with a spy center)

private final class SpyCenter: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var added: [PendingNotification] = []
    private(set) var removed: [String] = []
    private(set) var authorizationRequests = 0
    var pending: [String] = []

    func requestAuthorization() async -> Bool {
        lock.withLock { authorizationRequests += 1 }
        return true
    }

    func pendingIdentifiers() async -> [String] {
        lock.withLock { pending }
    }

    func add(_ notification: PendingNotification) async {
        lock.withLock { added.append(notification) }
    }

    func removePending(identifiers: [String]) async {
        lock.withLock { removed.append(contentsOf: identifiers) }
    }
}

@MainActor
@Suite("Earnings notification scheduler")
struct EarningsNotificationSchedulerTests {
    private func makeScheduler(_ center: SpyCenter, leadTime: Int = 1) -> EarningsNotificationScheduler {
        EarningsNotificationScheduler(
            center: center,
            leadTime: { leadTime },
            localCalendar: { newYork },
            localTimeZone: { eastern },
            now: { day("2026-06-25") }
        )
    }

    private let aapl = ReminderTarget(symbol: "AAPL", companyName: "Apple Inc", eventDate: day("2026-07-13"), session: .bmo)
    private let msft = ReminderTarget(symbol: "MSFT", companyName: "Microsoft Corp", eventDate: day("2026-07-14"), session: .amc)

    @Test func authorizationRequestedOnlyOnce() async {
        let center = SpyCenter()
        let scheduler = makeScheduler(center)
        await scheduler.requestAuthorizationIfNeeded()
        await scheduler.requestAuthorizationIfNeeded()
        #expect(center.authorizationRequests == 1)
    }

    @Test func syncSchedulesOneReminderPerTarget() async {
        let center = SpyCenter()
        let scheduler = makeScheduler(center)
        await scheduler.syncReminders(for: [aapl, msft])
        #expect(Set(center.added.map(\.id)) == ["reminder-AAPL", "reminder-MSFT"])
        #expect(center.added.allSatisfy { $0.fireDate != nil })
    }

    @Test func syncRemovesReminderForDroppedTicker() async {
        let center = SpyCenter()
        center.pending = ["reminder-AAPL", "reminder-MSFT"]
        let scheduler = makeScheduler(center)
        await scheduler.syncReminders(for: [aapl]) // MSFT gone
        #expect(center.removed == ["reminder-MSFT"])
        #expect(center.added.map(\.id) == ["reminder-AAPL"])
    }

    @Test func syncLeavesUnrelatedPendingIdentifiersAlone() async {
        let center = SpyCenter()
        center.pending = ["datechange-AAPL-123", "reminder-AAPL"]
        let scheduler = makeScheduler(center)
        await scheduler.syncReminders(for: [aapl])
        #expect(center.removed.isEmpty) // reminder-AAPL still desired; datechange untouched
    }

    @Test func handleDateChangeAddsOneImmediateAlert() async {
        let center = SpyCenter()
        let scheduler = makeScheduler(center)
        let change = DateChange(
            symbol: "AAPL", companyName: "Apple Inc",
            previousDate: day("2026-07-29"), newDate: day("2026-07-22"), newSession: .amc
        )
        await scheduler.handleDateChange(change)
        #expect(center.added.count == 1)
        #expect(center.added.first?.fireDate == nil)
        #expect(center.added.first?.title == "AAPL earnings moved")
    }
}
