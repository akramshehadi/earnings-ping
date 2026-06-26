import Foundation

/// Outcome of checking a candidate API key against the provider.
enum APIKeyValidationResult: Equatable, Sendable {
    /// The key authenticated successfully.
    case valid
    /// The provider rejected the key (missing or unauthorized).
    case invalid
    /// The check couldn't complete (network/transport problem); the key may or
    /// may not be good. Carries a short, user-facing reason.
    case networkError(String)
}

/// Validates a candidate API key before it is stored, so onboarding can reject a
/// bad key up front (acceptance: "invalid key rejected at onboarding").
protocol APIKeyValidating: Sendable {
    func validate(_ key: String) async -> APIKeyValidationResult
}

/// Validates a key by running a cheap symbol search through a *throwaway*
/// provider bound to the candidate key, so the check never touches — or
/// disturbs — the key currently stored in the Keychain.
struct FinnhubAPIKeyValidator: APIKeyValidating {
    /// Builds a provider bound to the candidate key. Injectable so tests can
    /// supply a fake provider and avoid the network.
    private let makeProvider: @Sendable (String) -> any EarningsProvider

    init(
        makeProvider: @escaping @Sendable (String) -> any EarningsProvider = { key in
            FinnhubProvider(apiKeyStore: InMemoryAPIKeyStore(key: key))
        }
    ) {
        self.makeProvider = makeProvider
    }

    func validate(_ key: String) async -> APIKeyValidationResult {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }

        do {
            // A non-empty result isn't required — a clean (non-auth) response is
            // enough to prove the token was accepted.
            _ = try await makeProvider(trimmed).searchSymbols(matching: "AAPL")
            return .valid
        } catch let error as EarningsProviderError {
            switch error {
            case .missingAPIKey, .unauthorized:
                return .invalid
            case .rateLimited:
                // A 429 means the token authenticated and was merely throttled,
                // so the key itself is good.
                return .valid
            case .network(let message):
                return .networkError(message)
            case .invalidResponse(let status):
                return .networkError("Unexpected response (HTTP \(status)).")
            case .decoding(let message):
                return .networkError(message)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }
}
