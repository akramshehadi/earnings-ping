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

    /// Stored provider API key (Keychain in the app, ADR-0003). Shared with the
    /// earnings provider so a key written during onboarding/settings is read on
    /// the provider's next call without rebuilding anything.
    let apiKeyStore: any APIKeyStoring

    /// Validates a candidate key before it is stored (onboarding/settings).
    let apiKeyValidator: any APIKeyValidating

    /// Observable login-item state for the settings toggle (issue 07).
    let loginItem: LoginItemController

    /// Earnings data source (Finnhub in v1, ADR-0003). Also conforms to
    /// `SymbolSearchProviding`. Used by the refresh engine (issue 04).
    let earningsProvider: any EarningsProvider

    /// Symbol autocomplete source for the Watchlist add field. Live Finnhub
    /// search once a key is configured, falling back to a local stub catalog
    /// before onboarding so the field keeps working with no key entered.
    let symbolSearch: any SymbolSearchProviding

    /// Schedules earnings reminders and posts immediate Date-Change alerts.
    let notificationScheduler: EarningsNotificationScheduler

    /// Drives earnings refresh (triggers, backoff, Date Change) over the store.
    /// Started from `AppDelegate.applicationDidFinishLaunching`.
    let refreshCoordinator: RefreshCoordinator

    init(
        settings: AppSettings? = nil,
        modelContainer: ModelContainer? = nil,
        apiKeyStore: (any APIKeyStoring)? = nil,
        apiKeyValidator: (any APIKeyValidating)? = nil,
        loginItem: LoginItemController? = nil,
        earningsProvider: (any EarningsProvider)? = nil,
        symbolSearch: (any SymbolSearchProviding)? = nil,
        notificationScheduler: EarningsNotificationScheduler? = nil,
        refreshCoordinator: RefreshCoordinator? = nil
    ) {
        let resolvedContainer = modelContainer ?? AppModelContainer.makeShared()
        let resolvedKeyStore = apiKeyStore ?? KeychainAPIKeyStore()
        let resolvedProvider = earningsProvider ?? FinnhubProvider(apiKeyStore: resolvedKeyStore)
        let resolvedSettings = settings ?? AppSettings()
        let resolvedScheduler = notificationScheduler
            ?? EarningsNotificationScheduler(
                center: UserNotificationCenterScheduler(),
                leadTime: { resolvedSettings.leadTimeTradingDays }
            )
        self.settings = resolvedSettings
        self.modelContainer = resolvedContainer
        self.apiKeyStore = resolvedKeyStore
        self.apiKeyValidator = apiKeyValidator ?? FinnhubAPIKeyValidator()
        self.loginItem = loginItem ?? LoginItemController()
        self.earningsProvider = resolvedProvider
        self.symbolSearch = symbolSearch
            ?? FallbackSymbolSearchProvider(primary: resolvedProvider, fallback: StubSymbolSearchProvider())
        self.notificationScheduler = resolvedScheduler
        self.refreshCoordinator = refreshCoordinator
            ?? RefreshCoordinator(
                provider: resolvedProvider,
                modelContainer: resolvedContainer,
                notifications: resolvedScheduler,
                interval: { .seconds(resolvedSettings.refreshIntervalHours * 3600) }
            )
    }

    /// Whether a usable API key is already stored — drives the first-run
    /// onboarding gate and the Settings welcome state.
    ///
    /// Reads the Keychain on a background task, never the main thread: a stored
    /// key can raise a per-item ACL prompt ("EarningsPing wants to use your
    /// confidential information…"), and a synchronous main-thread read would let
    /// that modal freeze app launch and hang `xcodebuild test` (issue 07
    /// carry-over). Awaiting here suspends rather than blocks, so the main thread
    /// stays responsive whether or not the prompt appears. The full fix — the
    /// data-protection keychain — needs an Apple-issued signing identity
    /// (self-signed/ad-hoc are AMFI-killed when they claim `keychain-access-groups`)
    /// and is deferred to the signing/enrollment issue (08).
    func hasStoredAPIKey() async -> Bool {
        await storedAPIKeyExists(in: apiKeyStore)
    }
}

/// Reads `store` off the main thread so a Keychain ACL prompt can never freeze
/// the caller. Backs `AppEnvironment.hasStoredAPIKey()`; kept as a free function
/// so it is unit-testable without standing up the whole composition root.
func storedAPIKeyExists(in store: any APIKeyStoring) async -> Bool {
    await Task.detached(priority: .utility) {
        let key = (try? store.apiKey()) ?? nil
        return key?.isEmpty == false
    }.value
}
