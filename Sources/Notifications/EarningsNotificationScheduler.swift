import Foundation

/// Schedules earnings reminders and posts immediate Date-Change alerts. The
/// trading-day math and text live in `NotificationFactory` / `TradingCalendar`;
/// this type owns the orchestration and talks to the notification center seam.
///
/// Driven by `RefreshCoordinator`: after every refresh pass it re-syncs
/// reminders from the store (rescheduling any that moved) and fires one
/// immediate alert per detected Date Change.
@MainActor
final class EarningsNotificationScheduler {
    private let center: NotificationScheduling
    private let tradingCalendar: TradingCalendar
    private let leadTime: () -> Int
    private let localCalendar: () -> Calendar
    private let localTimeZone: () -> TimeZone
    private let now: () -> Date

    private var didRequestAuthorization = false

    init(
        center: NotificationScheduling,
        leadTime: @escaping () -> Int,
        tradingCalendar: TradingCalendar = .nyse,
        localCalendar: @escaping () -> Calendar = { .current },
        localTimeZone: @escaping () -> TimeZone = { .current },
        now: @escaping () -> Date = Date.init
    ) {
        self.center = center
        self.leadTime = leadTime
        self.tradingCalendar = tradingCalendar
        self.localCalendar = localCalendar
        self.localTimeZone = localTimeZone
        self.now = now
    }

    /// Ask for alert permission once per process. Denied stays graceful — every
    /// later `add` simply no-ops at the center.
    func requestAuthorizationIfNeeded() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = await center.requestAuthorization()
    }

    /// Immediate "earnings moved" alert naming the new date + Session. The
    /// reminder itself is rescheduled by the following `syncReminders` pass.
    func handleDateChange(_ change: DateChange) async {
        await center.add(NotificationFactory.dateChange(change, localTimeZone: localTimeZone()))
    }

    /// Bring scheduled reminders in line with the current watchlist: (re)schedule
    /// a morning reminder for every target whose fire time is still in the
    /// future, and cancel any leftover reminders (ticker removed, event cleared,
    /// or the fire time has passed). Adding with the same identifier replaces the
    /// existing request, so a moved date reschedules in place.
    func syncReminders(for targets: [ReminderTarget]) async {
        let lead = leadTime()
        let calendar = localCalendar()
        let timeZone = localTimeZone()
        let asOf = now()

        var desired: [PendingNotification] = []
        for target in targets {
            guard let fireDate = NotificationFactory.reminderFireDate(
                eventDate: target.eventDate,
                leadTimeTradingDays: lead,
                tradingCalendar: tradingCalendar,
                localCalendar: calendar,
                now: asOf
            ) else { continue }
            desired.append(NotificationFactory.reminder(for: target, fireDate: fireDate, localTimeZone: timeZone))
        }

        let desiredIDs = Set(desired.map(\.id))
        let pending = await center.pendingIdentifiers()
        let stale = pending.filter { NotificationFactory.isReminderID($0) && !desiredIDs.contains($0) }
        if !stale.isEmpty {
            await center.removePending(identifiers: stale)
        }

        for notification in desired {
            await center.add(notification)
        }
    }
}
