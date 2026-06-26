import SwiftData
import SwiftUI

/// Composition root: the single object that wires the app's collaborators
/// together and hands them to the SwiftUI view tree via `@EnvironmentObject`.
///
/// Later issues hang their dependencies here (earnings provider, refresh
/// engine, notification scheduler, …).
@MainActor
final class AppEnvironment: ObservableObject {
    let settings: AppSettings

    /// SwiftData source-of-truth store, injected into the view tree.
    let modelContainer: ModelContainer

    /// Earnings data source (Finnhub in v1, ADR-0003). Also conforms to
    /// `SymbolSearchProviding`. Used by the refresh engine (issue 04).
    let earningsProvider: any EarningsProvider

    /// Symbol autocomplete source for the Watchlist add field. Still the local
    /// stub: the in-app swap to live Finnhub search lands with key onboarding
    /// (issue 07), so the field keeps working before a key is entered.
    let symbolSearch: any SymbolSearchProviding

    init(
        settings: AppSettings? = nil,
        modelContainer: ModelContainer? = nil,
        earningsProvider: (any EarningsProvider)? = nil,
        symbolSearch: (any SymbolSearchProviding)? = nil
    ) {
        self.settings = settings ?? AppSettings()
        self.modelContainer = modelContainer ?? AppModelContainer.makeShared()
        self.earningsProvider = earningsProvider ?? FinnhubProvider(apiKeyStore: InMemoryAPIKeyStore())
        self.symbolSearch = symbolSearch ?? StubSymbolSearchProvider()
    }
}
