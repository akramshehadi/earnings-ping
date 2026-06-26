import SwiftData
import SwiftUI

/// Itsycal-style month grid for the menu-bar popover: days carrying an Earnings
/// Event are highlighted, today is ringed, the month pages with the chevrons,
/// and selecting a day reveals its events below.
///
/// Driven by `@Query` over `EarningsEvent` directly (not `Ticker`) so the grid
/// reacts when a refresh or a Date Change moves an event's `date` — a change to
/// the event's own property, which a `Ticker` query would not necessarily see.
struct MonthCalendarView: View {
    @Query private var events: [EarningsEvent]

    private let grid = CalendarGrid()

    /// First-of-month currently displayed; starts on the current month.
    @State private var visibleMonth: Date = CalendarGrid().startOfMonth(for: .now)
    /// Day whose events are shown in the detail strip; defaults to today.
    @State private var selectedDay: Date = CalendarGrid().dayKey(for: .now)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            weekdayRow
            monthGrid
            Divider()
            DayDetailView(date: selectedDay, events: eventsByDay[selectedDay] ?? [], calendar: grid)
        }
        .padding(12)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Text(monthTitle(visibleMonth))
                .font(.headline)
            Spacer()
            Button { page(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month")
            Button("Today") { goToToday() }
                .font(.caption)
            Button { page(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next month")
        }
        .buttonStyle(.borderless)
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(grid.weekdaySymbols(), id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(grid.days(for: visibleMonth)) { day in
                DayCell(
                    day: day,
                    isToday: grid.isSameDay(day.date, .now),
                    isSelected: grid.isSameDay(day.date, selectedDay),
                    hasEarnings: eventsByDay[day.date]?.isEmpty == false,
                    dayNumber: dayNumber(day.date)
                )
                .onTapGesture { selectedDay = day.date }
            }
        }
    }

    // MARK: Data

    /// Upcoming Earnings Events bucketed by their NY report day, so a grid cell
    /// can ask "does this day carry earnings?" and the detail strip can list them.
    private var eventsByDay: [Date: [EarningsEvent]] {
        Dictionary(grouping: events.filter { $0.ticker != nil }) { grid.dayKey(for: $0.date) }
    }

    // MARK: Navigation

    private func page(by months: Int) {
        visibleMonth = grid.month(byAddingMonths: months, to: visibleMonth)
    }

    private func goToToday() {
        visibleMonth = grid.startOfMonth(for: .now)
        selectedDay = grid.dayKey(for: .now)
    }

    // MARK: Formatting

    private func monthTitle(_ date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String {
        String(grid.calendar.component(.day, from: date))
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
}

/// A single day in the month grid: number, today ring, earnings dot, selection.
private struct DayCell: View {
    let day: CalendarDay
    let isToday: Bool
    let isSelected: Bool
    let hasEarnings: Bool
    let dayNumber: String

    var body: some View {
        VStack(spacing: 1) {
            Text(dayNumber)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(numberColor)
            Circle()
                .fill(hasEarnings ? Color.accentColor : .clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(background)
        .contentShape(Rectangle())
    }

    private var numberColor: HierarchicalShapeStyle {
        day.isInMonth ? .primary : .quaternary
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18))
        } else if isToday {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1)
        }
    }
}

/// The strip under the grid: lists the selected day's Earnings Events with their
/// Session, fiscal period, EPS estimate, and freshness, or an empty note.
private struct DayDetailView: View {
    let date: Date
    let events: [EarningsEvent]
    let calendar: CalendarGrid

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.dayFormatter.string(from: date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if events.isEmpty {
                Text("No earnings on this day")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(sortedEvents, id: \.persistentModelID) { event in
                    EventDetailRow(event: event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Stable ordering within a day so rows don't jump around on refresh.
    private var sortedEvents: [EarningsEvent] {
        events.sorted { ($0.ticker?.symbol ?? "") < ($1.ticker?.symbol ?? "") }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

/// One Earnings Event in the day-detail strip.
private struct EventDetailRow: View {
    let event: EarningsEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(event.ticker?.symbol ?? "—")
                    .fontWeight(.semibold)
                Text(event.session.shortLabel)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
                Spacer(minLength: 4)
                if let period = event.fiscalPeriod {
                    Text(period)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let company = event.ticker?.companyName {
                Text(company)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let eps = event.epsEstimate {
                    Text("EPS est. \(eps, format: .number.precision(.fractionLength(2)))")
                }
                Text("·")
                Text("updated \(event.lastFetchedAt, format: .relative(presentation: .named))")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
