import Foundation

/// Symbol autocomplete that prefers a live provider but falls back to a local
/// catalog when no key is configured yet (or the key is rejected), so the
/// Watchlist add field keeps working before first-run onboarding completes.
///
/// Only auth/missing-key failures fall back; other errors (network, rate limit)
/// propagate so the field doesn't silently swap live results for the tiny stub
/// catalog on a transient hiccup.
struct FallbackSymbolSearchProvider: SymbolSearchProviding {
    let primary: any SymbolSearchProviding
    let fallback: any SymbolSearchProviding

    func searchSymbols(matching query: String) async throws -> [SymbolMatch] {
        do {
            return try await primary.searchSymbols(matching: query)
        } catch EarningsProviderError.missingAPIKey, EarningsProviderError.unauthorized {
            return try await fallback.searchSymbols(matching: query)
        }
    }
}
