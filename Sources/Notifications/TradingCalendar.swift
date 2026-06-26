import Foundation

/// US equity-market trading-day calendar: weekends plus a bundled NYSE full-day
/// closure table, anchored to America/New_York. Used to count "trading days
/// before" an earnings date so reminders skip weekends and market holidays
/// (CONTEXT: *Lead Time* is measured in trading days, not calendar days).
///
/// The holiday table is static and covers 2024–2030. Observed weekday shifts
/// (e.g. Independence Day on a Saturday → the preceding Friday) and Good Friday
/// are baked in rather than computed; the table must be extended periodically.
/// One-off closures (e.g. national days of mourning) are intentionally omitted.
struct TradingCalendar: Sendable {
    private let calendar: Calendar
    /// Holidays as `year * 10000 + month * 100 + day` keys — an integer set
    /// avoids the `DateComponents` equality pitfalls (an unrequested
    /// `isLeapMonth` flag breaks `Set<DateComponents>` membership).
    private let holidayKeys: Set<Int>

    /// The shared NYSE calendar used throughout the app.
    static let nyse = TradingCalendar(holidayDays: TradingCalendar.nyseHolidayDays)

    init(
        holidayDays: [DateComponents],
        timeZone: TimeZone = TimeZone(identifier: "America/New_York")!
    ) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
        self.holidayKeys = Set(holidayDays.compactMap(Self.key))
    }

    /// True if `date`'s calendar day (in NY) is a weekday and not a holiday.
    func isTradingDay(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sun … 7 = Sat
        if weekday == 1 || weekday == 7 { return false }
        guard let key = Self.key(calendar.dateComponents([.year, .month, .day], from: date)) else { return true }
        return !holidayKeys.contains(key)
    }

    private static func key(_ comps: DateComponents) -> Int? {
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
        return y * 10_000 + m * 100 + d
    }

    /// The trading day that is `count` trading days strictly before `date`.
    /// With `count == 0`, returns the start of `date`'s own day. Steps back one
    /// calendar day at a time, skipping weekends and holidays.
    func tradingDay(before date: Date, count: Int) -> Date {
        var cursor = calendar.startOfDay(for: date)
        var remaining = max(count, 0)
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
            if isTradingDay(cursor) { remaining -= 1 }
        }
        return cursor
    }

    /// Year/month/day of `date` in this calendar's (NY) time zone — used to
    /// re-anchor an NY trading day to a local wall-clock reminder time.
    func dayComponents(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }
}

extension TradingCalendar {
    private static func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Bundled NYSE full-day market closures, 2024–2030 (observed dates).
    /// New Year's Day, MLK Day, Washington's Birthday, Good Friday, Memorial
    /// Day, Juneteenth, Independence Day, Labor Day, Thanksgiving, Christmas.
    static let nyseHolidayDays: [DateComponents] = [
        // 2024
        day(2024, 1, 1), day(2024, 1, 15), day(2024, 2, 19), day(2024, 3, 29),
        day(2024, 5, 27), day(2024, 6, 19), day(2024, 7, 4), day(2024, 9, 2),
        day(2024, 11, 28), day(2024, 12, 25),
        // 2025
        day(2025, 1, 1), day(2025, 1, 20), day(2025, 2, 17), day(2025, 4, 18),
        day(2025, 5, 26), day(2025, 6, 19), day(2025, 7, 4), day(2025, 9, 1),
        day(2025, 11, 27), day(2025, 12, 25),
        // 2026
        day(2026, 1, 1), day(2026, 1, 19), day(2026, 2, 16), day(2026, 4, 3),
        day(2026, 5, 25), day(2026, 6, 19), day(2026, 7, 3), day(2026, 9, 7),
        day(2026, 11, 26), day(2026, 12, 25),
        // 2027
        day(2027, 1, 1), day(2027, 1, 18), day(2027, 2, 15), day(2027, 3, 26),
        day(2027, 5, 31), day(2027, 6, 18), day(2027, 7, 5), day(2027, 9, 6),
        day(2027, 11, 25), day(2027, 12, 24),
        // 2028 (Jan 1 falls on Saturday — not observed)
        day(2028, 1, 17), day(2028, 2, 21), day(2028, 4, 14), day(2028, 5, 29),
        day(2028, 6, 19), day(2028, 7, 4), day(2028, 9, 4), day(2028, 11, 23),
        day(2028, 12, 25),
        // 2029
        day(2029, 1, 1), day(2029, 1, 15), day(2029, 2, 19), day(2029, 3, 30),
        day(2029, 5, 28), day(2029, 6, 19), day(2029, 7, 4), day(2029, 9, 3),
        day(2029, 11, 22), day(2029, 12, 25),
        // 2030
        day(2030, 1, 1), day(2030, 1, 21), day(2030, 2, 18), day(2030, 4, 19),
        day(2030, 5, 27), day(2030, 6, 19), day(2030, 7, 4), day(2030, 9, 2),
        day(2030, 11, 28), day(2030, 12, 25),
    ]
}
