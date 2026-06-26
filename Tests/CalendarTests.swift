import Foundation
import Testing
@testable import EarningsPing

/// NY-anchored day parser, matching how the app stores earnings dates and how
/// the calendar grid keys its cells.
private let nyDay = FinnhubProvider.dayFormatter
private func day(_ ymd: String) -> Date { nyDay.date(from: ymd)! }

// MARK: - Month grid

@Suite("Calendar grid")
struct CalendarGridTests {
    private let grid = CalendarGrid()   // Sunday-first, NY-anchored

    @Test func gridIsAlwaysSixFullWeeks() {
        #expect(grid.days(for: day("2026-07-15")).count == 42)
        // February of a common year still fills six weeks (no reflow).
        #expect(grid.days(for: day("2026-02-15")).count == 42)
    }

    /// July 2026: the 1st is a Wednesday, so (Sunday-first) three leading days
    /// from June precede it.
    @Test func leadingDaysSpillFromPreviousMonth() {
        let days = grid.days(for: day("2026-07-10"))
        #expect(days[0].date == day("2026-06-28"))   // Sunday
        #expect(days[0].isInMonth == false)
        #expect(days[2].date == day("2026-06-30"))
        #expect(days[2].isInMonth == false)
        #expect(days[3].date == day("2026-07-01"))   // the 1st
        #expect(days[3].isInMonth == true)
    }

    @Test func gridStartsOnConfiguredFirstWeekday() {
        // Sunday-first: first cell is a Sunday (weekday 1).
        let sundayFirst = grid.days(for: day("2026-07-10"))
        #expect(grid.calendar.component(.weekday, from: sundayFirst[0].date) == 1)

        // Monday-first: the same month starts one day later, on Mon Jun 29.
        let mondayGrid = CalendarGrid(firstWeekday: 2)
        let mondayFirst = mondayGrid.days(for: day("2026-07-10"))
        #expect(mondayFirst[0].date == day("2026-06-29"))
        #expect(mondayGrid.calendar.component(.weekday, from: mondayFirst[0].date) == 2)
    }

    @Test func weekdaySymbolsHaveSevenEntries() {
        #expect(grid.weekdaySymbols().count == 7)
    }

    @Test func monthNavigationWrapsAcrossYears() {
        let dec = day("2026-12-15")
        #expect(grid.month(byAddingMonths: 1, to: dec) == day("2027-01-01"))
        let jan = day("2026-01-15")
        #expect(grid.month(byAddingMonths: -1, to: jan) == day("2025-12-01"))
    }

    @Test func sameDayAndMonthComparisons() {
        #expect(grid.isSameDay(day("2026-07-10"), day("2026-07-10")))
        #expect(grid.isSameDay(day("2026-07-10"), day("2026-07-11")) == false)
        #expect(grid.isSameMonth(day("2026-07-01"), day("2026-07-31")))
        #expect(grid.isSameMonth(day("2026-07-31"), day("2026-08-01")) == false)
    }
}

// MARK: - Imminent Window badge

@Suite("Imminent Window")
struct ImminentWindowTests {
    private let window = ImminentWindow()

    @Test func daysUntilCountsWholeNYDays() {
        #expect(window.daysUntil(day("2026-07-08"), from: day("2026-07-08")) == 0)
        #expect(window.daysUntil(day("2026-07-11"), from: day("2026-07-08")) == 3)
        #expect(window.daysUntil(day("2026-07-05"), from: day("2026-07-08")) == -3) // past
    }

    @Test func badgePicksSoonestEventInsideWindow() {
        let now = day("2026-07-08")
        let state = window.badge(
            for: [day("2026-07-11"), day("2026-07-09"), day("2026-07-20")],
            now: now,
            thresholdDays: 3
        )
        #expect(state == .imminent(daysUntil: 1))
    }

    @Test func badgeIncludesEventExactlyAtThreshold() {
        let state = window.badge(for: [day("2026-07-11")], now: day("2026-07-08"), thresholdDays: 3)
        #expect(state == .imminent(daysUntil: 3))
    }

    @Test func badgeIsNoneWhenBeyondWindow() {
        let state = window.badge(for: [day("2026-07-20")], now: day("2026-07-08"), thresholdDays: 3)
        #expect(state == .none)
    }

    /// Acceptance: the badge clears once an event passes — past dates never badge.
    @Test func badgeIgnoresPastEvents() {
        let state = window.badge(for: [day("2026-07-05")], now: day("2026-07-08"), thresholdDays: 3)
        #expect(state == .none)
    }

    @Test func badgeForTodayCountsZero() {
        let state = window.badge(for: [day("2026-07-08")], now: day("2026-07-08"), thresholdDays: 3)
        #expect(state == .imminent(daysUntil: 0))
    }
}
