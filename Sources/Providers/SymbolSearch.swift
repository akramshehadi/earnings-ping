import Foundation

/// One autocomplete result: a US-listed symbol and its resolved company name.
struct SymbolMatch: Identifiable, Hashable, Sendable {
    let symbol: String
    let companyName: String
    var id: String { symbol }
}

/// Type-to-search symbol lookup for the Watchlist add field.
///
/// Issue 02 ships a local stub conformer (`StubSymbolSearchProvider`); issue 03
/// replaces it with the Finnhub symbol-search endpoint behind this same
/// protocol. The full `EarningsProvider` (issue 03) composes this capability.
protocol SymbolSearchProviding: Sendable {
    /// US-listed symbol matches for a partial query. An empty query returns `[]`.
    func searchSymbols(matching query: String) async throws -> [SymbolMatch]
}
