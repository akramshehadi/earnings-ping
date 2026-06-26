import Foundation

/// Read access to the provider API key. The earnings provider depends only on
/// this narrow protocol and reads the key lazily on each call, so onboarding can
/// populate it after the provider is constructed.
protocol APIKeyProviding: Sendable {
    /// The stored key, or `nil` if the user hasn't onboarded one yet.
    func apiKey() throws -> String?
}

/// Read/write access to the stored key, used by first-run onboarding and the
/// settings UI (issue 07). Kept separate from `APIKeyProviding` so the provider
/// can't accidentally mutate the key it reads.
protocol APIKeyStoring: APIKeyProviding {
    /// Persist `key`. A blank/whitespace value clears any stored key.
    func setKey(_ key: String) throws
    /// Remove any stored key.
    func deleteKey() throws
}

/// In-memory, process-lifetime key holder for tests and previews. Seeds from the
/// `FINNHUB_API_KEY` environment variable when present so live integration tests
/// and local runs can supply a key without a UI or any committed secret.
final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
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

    func setKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock { self.key = trimmed.isEmpty ? nil : trimmed }
    }

    func deleteKey() throws {
        lock.withLock { key = nil }
    }
}
