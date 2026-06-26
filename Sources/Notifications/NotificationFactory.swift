import Foundation

/// A ticker's current upcoming event reduced to the fields a reminder needs.
/// Decouples the scheduler from SwiftData `@Model` types so the timing/text
/// logic is unit-testable with plain values.
struct ReminderTarget: Equatable, Sendable {
    let symbol: String
    let companyName: String
    let eventDate: Date
    let session: Session
}

/// Pure builders for reminder / Date-Change notification content and fire times.
/// Earnings dates are anchored to a NY calendar day; the *date* is always shown
/// in ET, while the cutoff *time* is converted to the user's local zone
/// (CONTEXT/PRD: "the user's local-time equivalent of the ET cutoff").
enum NotificationFactory {
    /// Local wall-clock hour the morning reminder fires.
    static let morningHour = 8

    private static let newYork = TimeZone(identifier: "America/New_York")!

    // MARK: Identifiers

    static func reminderID(symbol: String) -> String { "reminder-\(symbol)" }
    static func isReminderID(_ id: String) -> Bool { id.hasPrefix("reminder-") }

    /// Unique per move so each Date Change delivers its own (non-replacing) alert.
    static func dateChangeID(symbol: String, newDate: Date) -> String {
        "datechange-\(symbol)-\(Int(newDate.timeIntervalSince1970))"
    }

    // MARK: Reminder

    /// The instant a reminder should fire: `leadTimeTradingDays` trading days
    /// before the event, at the morning hour in the user's local time. Returns
    /// `nil` when that instant is already past (nothing to schedule).
    static func reminderFireDate(
        eventDate: Date,
        leadTimeTradingDays: Int,
        tradingCalendar: TradingCalendar,
        localCalendar: Calendar,
        now: Date
    ) -> Date? {
        let reminderDay = tradingCalendar.tradingDay(before: eventDate, count: leadTimeTradingDays)
        let ny = tradingCalendar.dayComponents(reminderDay)

        var comps = DateComponents()
        comps.year = ny.year
        comps.month = ny.month
        comps.day = ny.day
        comps.hour = morningHour
        comps.minute = 0

        guard let fire = localCalendar.date(from: comps), fire > now else { return nil }
        return fire
    }

    static func reminder(
        for target: ReminderTarget,
        fireDate: Date,
        localTimeZone: TimeZone
    ) -> PendingNotification {
        PendingNotification(
            id: reminderID(symbol: target.symbol),
            title: "\(target.symbol) reports \(weekdayDate(target.eventDate))",
            body: sessionBody(session: target.session, eventDate: target.eventDate, localTimeZone: localTimeZone),
            fireDate: fireDate
        )
    }

    // MARK: Date Change

    static func dateChange(_ change: DateChange, localTimeZone: TimeZone) -> PendingNotification {
        let newStr = monthDay(change.newDate)
        let oldStr = monthDay(change.previousDate)
        return PendingNotification(
            id: dateChangeID(symbol: change.symbol, newDate: change.newDate),
            title: "\(change.symbol) earnings moved",
            body: "Now \(newStr), \(change.newSession.shortLabel) (was \(oldStr))",
            fireDate: nil
        )
    }

    // MARK: Text helpers

    /// Session line, with the local-time equivalent of the ET cutoff appended
    /// when the session has one (BMO → open, AMC → close).
    static func sessionBody(session: Session, eventDate: Date, localTimeZone: TimeZone) -> String {
        if let local = localCutoffString(session: session, eventDate: eventDate, localTimeZone: localTimeZone) {
            return "\(session.longLabel) — \(local) your time"
        }
        return session.longLabel
    }

    /// The ET cutoff for `session` on `eventDate`, expressed in the user's local
    /// time (e.g. BMO's 9:30 AM ET → "6:30 AM" in Pacific). Nil for DMH/unknown.
    static func localCutoffString(session: Session, eventDate: Date, localTimeZone: TimeZone) -> String? {
        guard let cutoff = session.etCutoff else { return nil }

        var nyCal = Calendar(identifier: .gregorian)
        nyCal.timeZone = newYork
        let ny = nyCal.dateComponents([.year, .month, .day], from: eventDate)

        var comps = DateComponents()
        comps.timeZone = newYork
        comps.year = ny.year
        comps.month = ny.month
        comps.day = ny.day
        comps.hour = cutoff.hour
        comps.minute = cutoff.minute
        guard let etDate = nyCal.date(from: comps) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = localTimeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: etDate)
    }

    /// Event date as an ET weekday + short date, e.g. "Mon, Jul 13".
    private static func weekdayDate(_ date: Date) -> String {
        format(date, "EEE, MMM d")
    }

    /// Event date as an ET short date, e.g. "Jul 22".
    private static func monthDay(_ date: Date) -> String {
        format(date, "MMM d")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = newYork
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

extension Session {
    /// The ET wall-clock cutoff this session refers to: market open (9:30) for
    /// BMO, market close (16:00) for AMC. DMH/unknown have no single cutoff.
    var etCutoff: (hour: Int, minute: Int)? {
        switch self {
        case .bmo: return (9, 30)
        case .amc: return (16, 0)
        case .dmh, .unknown: return nil
        }
    }
}
