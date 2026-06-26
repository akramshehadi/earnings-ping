import Foundation

/// A single earnings announcement as returned by a provider — a plain value
/// type, decoupled from the SwiftData `EarningsEvent` model. The refresh engine
/// (issue 04) maps this onto the stored model.
struct UpcomingEarnings: Equatable, Sendable {
    let symbol: String
    /// Expected report day, anchored to America/New_York (midnight NY).
    let date: Date
    let session: Session
    /// e.g. "Q3 FY2026" — display only.
    let fiscalPeriod: String?
    let epsEstimate: Double?
    let fetchedAt: Date
}

/// Typed failures from a provider, so callers (issue 04) can react — e.g. retry
/// network/rate-limit errors with backoff, but surface `unauthorized` to the user.
enum EarningsProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case rateLimited
    case invalidResponse(status: Int)
    case network(String)
    case decoding(String)
}

/// Swappable earnings data source (ADR-0003). Composes symbol search with an
/// earnings-calendar fetch. Finnhub is the v1 implementation.
protocol EarningsProvider: SymbolSearchProviding {
    /// Earnings events for `symbol` whose date falls within `window`.
    /// US-listed equities only.
    func fetchEarnings(symbol: String, within window: DateInterval) async throws -> [UpcomingEarnings]
}

extension EarningsProvider {
    /// The soonest event on or after `window.start`, or `nil` if none.
    func nextUpcomingEarnings(symbol: String, within window: DateInterval) async throws -> UpcomingEarnings? {
        try await fetchEarnings(symbol: symbol, within: window)
            .filter { $0.date >= window.start }
            .min { $0.date < $1.date }
    }
}
