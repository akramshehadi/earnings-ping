import Foundation

/// Source of the provider API key. The real Keychain-backed implementation and
/// the first-run onboarding that populates it land in issue 07; until then the
/// provider reads through this abstraction so the wiring doesn't change later.
protocol APIKeyProviding: Sendable {
    /// The stored key, or `nil` if the user hasn't onboarded one yet.
    func apiKey() throws -> String?
}

/// Temporary, process-lifetime key holder used until the Keychain wrapper
/// (issue 07) exists. Seeds from the `FINNHUB_API_KEY` environment variable when
/// present so live integration tests and local runs can supply a key without a
/// UI or any committed secret.
final class InMemoryAPIKeyStore: APIKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = ProcessInfo.processInfo.environment["FINNHUB_API_KEY"]) {
        // Treat blank/whitespace env values as "no key".
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func apiKey() throws -> String? {
        lock.withLock { key }
    }

    func setKey(_ newKey: String?) {
        let trimmed = newKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock { key = (trimmed?.isEmpty == false) ? trimmed : nil }
    }
}
