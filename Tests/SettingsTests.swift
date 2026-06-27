import Foundation
import Testing
@testable import EarningsPing

// MARK: - Fakes

/// Earnings provider whose `searchSymbols` returns a canned result, so the key
/// validator can be exercised without the network.
private struct FakeProvider: EarningsProvider {
    let searchResult: Result<[SymbolMatch], EarningsProviderError>

    func searchSymbols(matching query: String) async throws -> [SymbolMatch] {
        try searchResult.get()
    }

    func fetchEarnings(symbol: String, within window: DateInterval) async throws -> [UpcomingEarnings] {
        []
    }
}

/// In-memory login item for the controller tests; can be told to fail on write.
private final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private let shouldFail: Bool

    init(enabled: Bool = false, shouldFail: Bool = false) {
        self.enabled = enabled
        self.shouldFail = shouldFail
    }

    enum Failure: Error { case denied }

    var isEnabled: Bool { lock.withLock { enabled } }

    func setEnabled(_ newValue: Bool) throws {
        if shouldFail { throw Failure.denied }
        lock.withLock { enabled = newValue }
    }
}

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "EarningsPingTests-\(UUID().uuidString)")!
}

// MARK: - API key validation

@Suite("API key validation")
struct APIKeyValidatorTests {
    @Test func acceptsAKeyThatAuthenticates() async {
        let validator = FinnhubAPIKeyValidator(makeProvider: { _ in
            FakeProvider(searchResult: .success([SymbolMatch(symbol: "AAPL", companyName: "Apple Inc")]))
        })
        #expect(await validator.validate("good-key") == .valid)
    }

    /// A clean response with no matches still proves the token was accepted.
    @Test func acceptsAnAuthenticatedEmptyResult() async {
        let validator = FinnhubAPIKeyValidator(makeProvider: { _ in
            FakeProvider(searchResult: .success([]))
        })
        #expect(await validator.validate("good-key") == .valid)
    }

    @Test func rejectsAnUnauthorizedKey() async {
        let validator = FinnhubAPIKeyValidator(makeProvider: { _ in
            FakeProvider(searchResult: .failure(.unauthorized))
        })
        #expect(await validator.validate("bad-key") == .invalid)
    }

    @Test func rejectsBlankInputWithoutBuildingAProvider() async {
        let validator = FinnhubAPIKeyValidator(makeProvider: { _ in
            Issue.record("validator should short-circuit on blank input")
            return FakeProvider(searchResult: .success([]))
        })
        #expect(await validator.validate("   ") == .invalid)
    }

    /// A 429 means the token authenticated and was merely throttled — the key works.
    @Test func treatsRateLimitAsValid() async {
        let validator = FinnhubAPIKeyValidator(makeProvider: { _ in
            FakeProvider(searchResult: .failure(.rateLimited))
        })
        #expect(await validator.validate("good-key") == .valid)
    }

    @Test func surfacesNetworkErrorsWithoutCondemningTheKey() async {
        let validator = FinnhubAPIKeyValidator(makeProvider: { _ in
            FakeProvider(searchResult: .failure(.network("offline")))
        })
        #expect(await validator.validate("good-key") == .networkError("offline"))
    }
}

// MARK: - Stored-key contract

@Suite("API key store")
struct APIKeyStoreTests {
    @Test func setsTrimsAndClears() throws {
        let store = InMemoryAPIKeyStore(key: nil)
        #expect(try store.apiKey() == nil)

        try store.setKey("  abc123  ")
        #expect(try store.apiKey() == "abc123")

        // A blank value clears the stored key.
        try store.setKey("   ")
        #expect(try store.apiKey() == nil)

        try store.setKey("xyz")
        try store.deleteKey()
        #expect(try store.apiKey() == nil)
    }

    /// With nothing stored, the Keychain store falls back to the supplied
    /// environment value (the integration-test escape hatch). Uses a unique
    /// service so it can't collide with a real entry.
    @Test func keychainStoreFallsBackToEnvironmentWhenEmpty() throws {
        let store = KeychainAPIKeyStore(
            service: "EarningsPingTests-\(UUID().uuidString)",
            environmentFallback: "env-key"
        )
        #expect(try store.apiKey() == "env-key")
    }
}

// MARK: - Off-main-thread key presence (issue 08)

/// `storedAPIKeyExists(in:)` backs the first-run launch gate and the Settings
/// window's onboarding state. It must read the key off the main thread so a
/// Keychain ACL prompt can never freeze launch (issue 07 carry-over); these
/// tests pin its presence logic.
@Suite("Stored-key presence (off-main-thread)")
struct StoredAPIKeyPresenceTests {
    @Test func reportsTrueWhenAKeyIsStored() async {
        #expect(await storedAPIKeyExists(in: InMemoryAPIKeyStore(key: "abc123")) == true)
    }

    @Test func reportsFalseWhenEmpty() async {
        #expect(await storedAPIKeyExists(in: InMemoryAPIKeyStore(key: nil)) == false)
    }

    /// With nothing in the Keychain, the environment fallback still counts as a
    /// usable key. Uses a unique service so it can't collide with a real entry.
    @Test func countsTheEnvironmentFallbackAsPresent() async {
        let store = KeychainAPIKeyStore(
            service: "EarningsPingTests-\(UUID().uuidString)",
            environmentFallback: "env-key"
        )
        #expect(await storedAPIKeyExists(in: store) == true)
    }
}

// MARK: - Refresh-interval setting

@Suite("Refresh interval setting")
@MainActor
struct RefreshIntervalSettingTests {
    @Test func defaultsToSixHours() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.refreshIntervalHours == 6)
    }

    @Test func clampsToBoundsAndPersists() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.refreshIntervalHours = 999
        #expect(settings.refreshIntervalHours == AppSettings.maxRefreshIntervalHours)

        settings.refreshIntervalHours = 0
        #expect(settings.refreshIntervalHours == AppSettings.minRefreshIntervalHours)

        // The clamped value survives a reload from the same defaults.
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.refreshIntervalHours == AppSettings.minRefreshIntervalHours)
    }
}

// MARK: - Launch at Login

@Suite("Launch at Login")
@MainActor
struct LoginItemControllerTests {
    @Test func togglingRegistersAndUnregisters() {
        let service = FakeLoginItem(enabled: false)
        let controller = LoginItemController(service: service)
        #expect(controller.isEnabled == false)

        controller.setEnabled(true)
        #expect(controller.isEnabled == true)
        #expect(service.isEnabled == true)

        controller.setEnabled(false)
        #expect(controller.isEnabled == false)
        #expect(service.isEnabled == false)
    }

    /// A failed registration leaves the toggle showing the true (unchanged)
    /// state and surfaces an error rather than lying about success.
    @Test func failedToggleKeepsTrueStateAndReportsError() {
        let service = FakeLoginItem(enabled: false, shouldFail: true)
        let controller = LoginItemController(service: service)

        controller.setEnabled(true)
        #expect(controller.isEnabled == false)
        #expect(controller.lastError != nil)
    }
}
