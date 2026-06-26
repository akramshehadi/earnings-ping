import Foundation
import Security

/// Keychain-backed store for the provider API key (ADR-0003: bring-your-own key
/// in the macOS Keychain, no backend). Conforms to `APIKeyStoring` so the
/// provider reads it lazily and onboarding/settings can write or clear it.
///
/// Backed by a single generic-password item keyed by `service` + `account`.
/// Reads fall back to the `FINNHUB_API_KEY` environment variable when the
/// Keychain holds nothing, preserving the local/integration-test escape hatch
/// the in-memory store offered.
///
/// The item is stored `kSecAttrAccessibleAfterFirstUnlock` so the background
/// agent can keep refreshing after the user has logged in once, without the
/// device needing to be unlocked at the moment of each refresh.
final class KeychainAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let service: String
    private let account: String
    private let environmentKey: String?

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.bootstrapbits.EarningsPing",
        account: String = "finnhub-api-key",
        environmentFallback: String? = ProcessInfo.processInfo.environment["FINNHUB_API_KEY"]
    ) {
        self.service = service
        self.account = account
        let trimmed = environmentFallback?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.environmentKey = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func apiKey() throws -> String? {
        if let stored = try readKeychain() { return stored }
        return environmentKey
    }

    func setKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { try deleteKey(); return }
        let data = Data(trimmed.utf8)

        // Update the existing item in place if present, otherwise insert one.
        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = baseQuery()
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        default:
            throw KeychainError.unhandled(status)
        }
    }

    func deleteKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    // MARK: - Private

    private func readKeychain() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let string = String(data: data, encoding: .utf8) else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// A Keychain `SecItem*` call returned an unexpected `OSStatus`.
enum KeychainError: Error, Equatable, CustomStringConvertible {
    case unhandled(OSStatus)

    var description: String {
        switch self {
        case .unhandled(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Keychain error \(status): \(message)"
        }
    }
}
