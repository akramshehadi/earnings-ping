import Foundation

/// A detected reschedule of an `EarningsEvent` (CONTEXT: *Date Change*) — a
/// first-class signal, never a silent overwrite. Emitted by the refresh engine
/// and consumed by the notification scheduler (issue 05).
struct DateChange: Equatable, Sendable {
    let symbol: String
    let companyName: String
    let previousDate: Date
    let newDate: Date
    let newSession: Session
}

/// Outcome of reconciling a stored event's date against a freshly fetched one.
enum EventReconciliation: Equatable, Sendable {
    /// No event was stored yet — this is the first known date.
    case created
    /// Same report day as before; only display fields may have moved.
    case unchanged
    /// The report day moved — a Date Change.
    case dateChanged(from: Date, to: Date)
}

/// Pure date-reconciliation logic, isolated from SwiftData and the network so it
/// can be unit-tested directly.
enum RefreshReconciler {
    /// Earnings dates are anchored to midnight America/New_York; compare by NY
    /// calendar day so a same-day refetch never reads as a move.
    static let newYorkCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    static func reconcile(existingDate: Date?, incomingDate: Date) -> EventReconciliation {
        guard let existingDate else { return .created }
        if newYorkCalendar.isDate(existingDate, inSameDayAs: incomingDate) {
            return .unchanged
        }
        return .dateChanged(from: existingDate, to: incomingDate)
    }
}
