import Foundation
import Security
import os

/// Keychain-backed `SecretStore`. Stores generic-password items scoped to a
/// service identifier supplied at init. Values are UTF-8 strings. Never logs values.
///
/// Reads are cached for the lifetime of the launch: on the legacy file-based
/// keychain, every `SecItem` call against an item whose ACL doesn't trust the
/// current binary (routine in development, where each rebuild is ad-hoc signed)
/// raises a password prompt — the cache caps that at one prompt per launch.
@MainActor
public final class KeychainSecretStore: SecretStore {

    private let service: String
    private let logger: Logger

    /// Per-launch cache. The inner optional distinguishes "cached: no item"
    /// from "not yet read".
    private var cache: [String: String?] = [:]

    /// - Parameter service: the Keychain service identifier, typically the app
    ///   bundle id (e.g. `"com.blazepascal.CareerPilot"`).

    // MARK: - Init
    public init(service: String) {
        self.service = service
        self.logger = Logger(subsystem: service, category: "Keychain")
    }

    // MARK: - SecretStore
    public func string(forKey key: String) -> String? {
        if let cached = cache[key] { return cached }
        return readThroughCache(forKey: key)
    }

    public func refreshedString(forKey key: String) -> String? {
        readThroughCache(forKey: key)
    }

    // MARK: - Private
    private func readThroughCache(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain read failed for \(key, privacy: .public): \(status)")
            }
            cache[key] = String?.none
            return nil
        }
        let value = String(data: data, encoding: .utf8)
        cache[key] = value
        return value
    }

    public func set(_ value: String, forKey key: String) {
        guard !value.isEmpty else {
            removeValue(forKey: key)
            return
        }
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let update: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status == errSecSuccess {
            cache[key] = value
        } else {
            logger.error("Keychain write failed for \(key, privacy: .public): \(status)")
        }
    }

    public func removeValue(forKey key: String) {
        cache[key] = String?.none
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed for \(key, privacy: .public): \(status)")
        }
    }
}
