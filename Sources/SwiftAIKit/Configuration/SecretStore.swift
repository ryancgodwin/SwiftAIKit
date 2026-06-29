import Foundation

/// Abstraction over secret storage (e.g. provider API keys).
///
/// Conforms to `Sendable` so that implementations can be captured in
/// `@Sendable` closures and passed across actor boundaries — enabling the
/// lazy-key-resolver pattern in `AnthropicProvider` where the key is read
/// only when a request is actually made, not at configure time.
///
/// Implementations must ensure their own thread-safety (see concrete types).
public protocol SecretStore: AnyObject, Sendable {

    /// Read a secret value.
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
///
/// Thread-safety is provided by an `NSLock` guarding all `storage` accesses,
/// allowing this type to be declared `@unchecked Sendable`. The lock makes
/// every read and write atomic.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        lock.withLock { storage[key] }
    }

    public func refreshedString(forKey key: String) -> String? {
        lock.withLock { storage[key] }
    }

    public func set(_ value: String, forKey key: String) {
        lock.withLock {
            if value.isEmpty {
                storage.removeValue(forKey: key)
            } else {
                storage[key] = value
            }
        }
    }

    public func removeValue(forKey key: String) {
        lock.withLock { _ = storage.removeValue(forKey: key) }
    }
}
