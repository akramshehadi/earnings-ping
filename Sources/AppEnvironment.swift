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

    /// Symbol autocomplete source. Stubbed in issue 02; the Finnhub client
    /// (issue 03) replaces it behind `SymbolSearchProviding`.
    let symbolSearch: any SymbolSearchProviding

    init(
        settings: AppSettings? = nil,
        modelContainer: ModelContainer? = nil,
        symbolSearch: (any SymbolSearchProviding)? = nil
    ) {
        self.settings = settings ?? AppSettings()
        self.modelContainer = modelContainer ?? AppModelContainer.makeShared()
        self.symbolSearch = symbolSearch ?? StubSymbolSearchProvider()
    }
}
