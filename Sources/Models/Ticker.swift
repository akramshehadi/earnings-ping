import Foundation
import SwiftData

/// A US-listed stock symbol the user is tracking. The Watchlist is the set of
/// these. This store is the app's source of truth (ADR-0001).
@Model
final class Ticker {
    /// Uppercase US-listed symbol, e.g. "AAPL". Unique within the store.
    @Attribute(.unique) var symbol: String

    /// Company name resolved at add time, e.g. "Apple Inc".
    var companyName: String

    var addedAt: Date

    /// The single next upcoming Earnings Event of interest, once a refresh
    /// populates it (issue 04). Nil until then. Deleting a Ticker cascades to
    /// its event, so removing a ticker drops its earnings date too.
    @Relationship(deleteRule: .cascade, inverse: \EarningsEvent.ticker)
    var event: EarningsEvent?

    init(symbol: String, companyName: String, addedAt: Date = .now) {
        self.symbol = symbol
        self.companyName = companyName
        self.addedAt = addedAt
    }
}
