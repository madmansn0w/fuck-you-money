import Foundation
import Security

/// Stores and retrieves exchange API credentials in the Keychain per (user, exchange).
/// Secrets are never written to disk or Settings.
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "FuckYouMoney.API"

    private init() {}

    /// Account identifier for Keychain: `username.exchange` so each user's keys are isolated.
    private func account(user: String, exchange: String) -> String {
        "\(user).\(exchange)"
    }

    /// Saves API key and secret for the given user and exchange.
    /// - Returns: true if save succeeded, false otherwise.
    func save(apiKey: String, secret: String, user: String, exchange: String) -> Bool {
        let accountId = account(user: user, exchange: exchange)
        let payload: [String: String] = ["k": apiKey, "s": secret]
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        delete(user: user, exchange: exchange)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Loads API key and secret for the given user and exchange.
    /// - Returns: Tuple (apiKey, secret) or nil if not found or invalid.
    func load(user: String, exchange: String) -> (apiKey: String, secret: String)? {
        let accountId = account(user: user, exchange: exchange)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let payload = try? JSONDecoder().decode([String: String].self, from: data),
              let k = payload["k"], let s = payload["s"], !k.isEmpty, !s.isEmpty
        else { return nil }
        return (k, s)
    }

    /// Removes stored credentials for the given user and exchange.
    func delete(user: String, exchange: String) {
        let accountId = account(user: user, exchange: exchange)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountId,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
