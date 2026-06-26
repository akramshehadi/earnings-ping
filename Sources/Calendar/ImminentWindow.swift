import Foundation

/// What the menu-bar icon badge should show: nothing, or a countdown to the
/// soonest upcoming Earnings Event that is inside the Imminent Window.
enum BadgeState: Equatable, Sendable {
    case none
    /// Soonest imminent event is `daysUntil` NY-calendar days away (0 = today).
    case imminent(daysUntil: Int)
}

/// Pure logic for the menu-bar "Imminent Window" badge: whether any upcoming
/// Earnings Event is close enough to badge the icon, and the countdown to the
/// soonest one (CONTEXT: *Imminent Window* — a glanceable ambient signal).
///
/// Distinct from *Lead Time*, which is trading-day based and drives the
/// notification reminder; the Imminent Window is measured in plain calendar
/// days, NY-anchored to match how Earnings Event dates are stored. Isolated
/// from SwiftUI so it can be unit-tested directly.
struct ImminentWindow: Sendable {
    private let calendar: Calendar

    init(timeZone: TimeZone = TimeZone(identifier: "America/New_York")!) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
    }

    /// Whole NY-calendar days from `now`'s day to `eventDate`'s day. `0` is the
    /// same day; negative means the event is already in the past.
    func daysUntil(_ eventDate: Date, from now: Date) -> Int {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: eventDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// The badge state for a set of upcoming event dates: the countdown to the
    /// soonest event that is today or within `thresholdDays` ahead, else `.none`.
    /// Past events and events beyond the window are ignored, so the badge clears
    /// on its own once the soonest event passes.
    func badge(for eventDates: [Date], now: Date, thresholdDays: Int) -> BadgeState {
        let withinWindow = eventDates
            .map { daysUntil($0, from: now) }
            .filter { $0 >= 0 && $0 <= thresholdDays }

        guard let soonest = withinWindow.min() else { return .none }
        return .imminent(daysUntil: soonest)
    }
}
