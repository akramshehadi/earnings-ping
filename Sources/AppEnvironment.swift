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

    /// Drives earnings refresh (triggers, backoff, Date Change) over the store.
    /// Started from `AppDelegate.applicationDidFinishLaunching`.
    let refreshCoordinator: RefreshCoordinator

    init(
        settings: AppSettings? = nil,
        modelContainer: ModelContainer? = nil,
        earningsProvider: (any EarningsProvider)? = nil,
        symbolSearch: (any SymbolSearchProviding)? = nil,
        refreshCoordinator: RefreshCoordinator? = nil
    ) {
        let resolvedContainer = modelContainer ?? AppModelContainer.makeShared()
        let resolvedProvider = earningsProvider ?? FinnhubProvider(apiKeyStore: InMemoryAPIKeyStore())
        self.settings = settings ?? AppSettings()
        self.modelContainer = resolvedContainer
        self.earningsProvider = resolvedProvider
        self.symbolSearch = symbolSearch ?? StubSymbolSearchProvider()
        self.refreshCoordinator = refreshCoordinator
            ?? RefreshCoordinator(provider: resolvedProvider, modelContainer: resolvedContainer)
    }
}
