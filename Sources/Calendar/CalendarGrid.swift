import Foundation

/// One cell in the month grid: a calendar day plus whether it belongs to the
/// month being shown (leading/trailing days from adjacent months fill the grid).
struct CalendarDay: Identifiable, Equatable, Sendable {
    /// Start of the day, NY-anchored — matches how Earnings Events are stored.
    let date: Date
    /// False for the leading/trailing spill-over days from the adjacent months.
    let isInMonth: Bool

    var id: Date { date }
}

/// Pure builder for an Itsycal-style month grid, NY-anchored so its day cells
/// line up with stored Earnings Event dates (which are midnight America/New_York).
///
/// The grid is always a fixed 6 weeks × 7 days = 42 cells, padded with the
/// adjacent months' edge days, so the popover never changes height as the user
/// pages between months. Day math is isolated here (no SwiftUI) so it can be
/// unit-tested directly, mirroring `TradingCalendar` / `WatchlistOperations`.
struct CalendarGrid: Sendable {
    /// Number of weeks shown — fixed so the grid never reflows between months.
    static let weekCount = 6
    static let dayCount = weekCount * 7

    let calendar: Calendar

    init(
        timeZone: TimeZone = TimeZone(identifier: "America/New_York")!,
        firstWeekday: Int = 1   // 1 = Sunday (US default)
    ) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = firstWeekday
        self.calendar = cal
    }

    /// The 42 days covering `month`, in display order, starting on the grid's
    /// `firstWeekday` of the week containing the 1st and running 6 weeks on.
    func days(for month: Date) -> [CalendarDay] {
        let firstOfMonth = startOfMonth(for: month)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        // How many leading days from the previous month precede the 1st.
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth)!

        return (0..<Self.dayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            let inMonth = calendar.isDate(date, equalTo: firstOfMonth, toGranularity: .month)
            return CalendarDay(date: calendar.startOfDay(for: date), isInMonth: inMonth)
        }
    }

    /// Short weekday symbols (e.g. "Sun"…"Sat"), rotated to start on the grid's
    /// `firstWeekday` so the header row aligns with the day columns.
    func weekdaySymbols() -> [String] {
        let symbols = calendar.shortWeekdaySymbols          // always Sunday-first
        let shift = calendar.firstWeekday - 1               // 0 for Sunday-first
        return (0..<7).map { symbols[($0 + shift) % 7] }
    }

    // MARK: Navigation

    /// Start of the month (NY) containing `date`.
    func startOfMonth(for date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps)!
    }

    /// The month `value` months away from `date`'s month (negative = earlier).
    func month(byAddingMonths value: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: value, to: startOfMonth(for: date))!
    }

    // MARK: Comparisons

    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    func isSameMonth(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    /// Stable per-day key for bucketing Earnings Events by their report day,
    /// matching the grid cells' NY-anchored start-of-day dates.
    func dayKey(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
