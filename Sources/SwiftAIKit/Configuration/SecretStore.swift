/// Abstraction over secret storage (e.g. provider API keys).
///
/// Production uses `KeychainSecretStore`; tests use `InMemorySecretStore`.
/// `@MainActor` because the Keychain implementation caches per-launch reads and
/// is consumed from `@MainActor` UI/readiness code.
@MainActor
public protocol SecretStore: AnyObject {

    /// Read a secret, possibly served from a per-launch cache.
    func string(forKey key: String) -> String?

    /// Read fresh, bypassing any cache — for explicit, user-initiated reveals.
    func refreshedString(forKey key: String) -> String?

    /// Store (or replace) a value. An empty string removes the item, so
    /// "cleared the field" and "no secret" are the same state.
    func set(_ value: String, forKey key: String)

    /// Remove a stored secret.
    func removeValue(forKey key: String)
}

/// In-memory `SecretStore` for tests and previews. Not persistent.
@MainActor
public final class InMemorySecretStore: SecretStore {

    private var storage: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? { storage[key] }

    public func refreshedString(forKey key: String) -> String? { storage[key] }

    public func set(_ value: String, forKey key: String) {
        guard !value.isEmpty else {
            storage.removeValue(forKey: key)
            return
        }
        storage[key] = value
    }

    public func removeValue(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}
