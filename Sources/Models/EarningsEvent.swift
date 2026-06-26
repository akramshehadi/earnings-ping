import Foundation
import SwiftData

/// The next upcoming earnings announcement for one `Ticker`. Treated as
/// *estimated* in v1 — free providers expose no reliable confirmed signal.
///
/// Not populated until the refresh engine (issue 04) fills it from the provider;
/// issue 02 only defines the model so the store schema is complete.
@Model
final class EarningsEvent {
    /// Owning ticker (inverse of `Ticker.event`).
    var ticker: Ticker?

    /// Expected report day, anchored to America/New_York.
    var date: Date

    /// Persisted raw value of `Session`; use the `session` accessor.
    var sessionRaw: String

    /// e.g. "Q2 FY2026" — display only.
    var fiscalPeriod: String?

    /// Consensus EPS estimate — optional, display only.
    var epsEstimate: Double?

    /// Single value "estimated" in v1; reserved for a future confirmed flag.
    var status: String

    var lastFetchedAt: Date

    /// Previously known `date`, used to detect a Date Change (issue 04).
    var previousDate: Date?

    var session: Session {
        get { Session(rawValue: sessionRaw) ?? .unknown }
        set { sessionRaw = newValue.rawValue }
    }

    init(
        date: Date,
        session: Session = .unknown,
        fiscalPeriod: String? = nil,
        epsEstimate: Double? = nil,
        status: String = "estimated",
        lastFetchedAt: Date = .now,
        previousDate: Date? = nil
    ) {
        self.date = date
        self.sessionRaw = session.rawValue
        self.fiscalPeriod = fiscalPeriod
        self.epsEstimate = epsEstimate
        self.status = status
        self.lastFetchedAt = lastFetchedAt
        self.previousDate = previousDate
    }
}
