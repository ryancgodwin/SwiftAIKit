import Foundation
import Testing
@testable import SwiftAIKit

// MARK: - Spy SecretStore

/// Spy `SecretStore` that tracks how many times `string(forKey:)` is called.
/// Used to prove the API key is NOT read at configure time.
final class SpySecretStore: SecretStore, @unchecked Sendable {

    private let lock = NSLock()
    private var _storage: [String: String] = [:]
    private var _readCount: Int = 0

    /// Total number of `string(forKey:)` invocations so far.
    var readCount: Int {
        lock.withLock { _readCount }
    }

    func string(forKey key: String) -> String? {
        lock.withLock {
            _readCount += 1
            return _storage[key]
        }
    }

    func refreshedString(forKey key: String) -> String? {
        lock.withLock {
            _readCount += 1
            return _storage[key]
        }
    }

    func set(_ value: String, forKey key: String) {
        lock.withLock {
            if value.isEmpty {
                _ = _storage.removeValue(forKey: key)
            } else {
                _storage[key] = value
            }
        }
    }

    func removeValue(forKey key: String) {
        lock.withLock { _ = _storage.removeValue(forKey: key) }
    }
}

// MARK: - Counter helper for @Sendable closures

/// A thread-safe counter that can be mutated from `@Sendable` closures.
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int { lock.withLock { _value } }

    func increment() { lock.withLock { _value += 1 } }
}

/// A thread-safe boolean flag that can be set from `@Sendable` closures.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool = false

    var value: Bool { lock.withLock { _value } }

    func set() { lock.withLock { _value = true } }
}

// MARK: - Tests

@MainActor
@Suite("Lazy Anthropic Key Loading")
struct LazyAnthropicKeyTests {

    // MARK: Test 1 — zero reads at configure time

    @Test("configureAnthropic(secretStore:) reads Keychain zero times at configure time")
    func configureTimeReadCountIsZero() {
        let router = AIServiceRouter(
            defaultProvider: .anthropic,
            defaultsKey: "test_lazy_1_\(UUID().uuidString)"
        )
        let spy = SpySecretStore()
        spy.set("sk-ant-lazily-loaded", forKey: BYOKConfiguration.default.apiKeyAccount)

        // This is the configure step — the bug was that it read the key here.
        ProviderConfigurator.configureAnthropic(
            router: router,
            secretStore: spy,
            config: .default
        )

        // Key must NOT have been read at configure time.
        #expect(spy.readCount == 0, "Keychain must not be touched at configure time")
    }

    // MARK: Test 2 — resolver takes precedence over static apiKey

    @Test("Configuration with apiKeyResolver uses resolver over static apiKey")
    func resolverTakesPrecedenceOverStaticKey() async {
        let resolverCalled = AtomicFlag()
        let config = AnthropicProvider.Configuration(
            apiKey: "static-key",
            apiKeyResolver: {
                resolverCalled.set()
                return "resolver-key"
            }
        )
        // Verify the config stored both values correctly.
        #expect(config.apiKeyResolver != nil)
        #expect(config.apiKey == "static-key")

        let provider = AnthropicProvider(configuration: config)
        // isAvailable must NOT call the resolver — resolverCalled stays false.
        let available = await provider.isAvailable
        #expect(available == true)
        #expect(resolverCalled.value == false, "isAvailable must not invoke the resolver")
    }

    @Test("Configuration with resolver returning nil falls back to static apiKey")
    func resolverNilFallsBackToStaticKey() async {
        let config = AnthropicProvider.Configuration(
            apiKey: "fallback-key",
            apiKeyResolver: { nil }
        )
        #expect(config.apiKey == "fallback-key")
        let provider = AnthropicProvider(configuration: config)
        let available = await provider.isAvailable
        #expect(available == true)
    }

    // MARK: Test 3 — isAvailable with resolver, without calling it

    @Test("isAvailable returns true when resolver is set, without reading it (spy stays at 0)")
    func isAvailableWithResolverNoRead() async {
        let spy = SpySecretStore()
        spy.set("sk-ant-key", forKey: BYOKConfiguration.default.apiKeyAccount)

        let resolverInvokeCount = AtomicCounter()
        let config = AnthropicProvider.Configuration(
            apiKey: "",
            apiKeyResolver: {
                resolverInvokeCount.increment()
                return spy.string(forKey: BYOKConfiguration.default.apiKeyAccount)
            }
        )

        let provider = AnthropicProvider(configuration: config)
        let available = await provider.isAvailable

        #expect(available == true, "isAvailable must be true when resolver is set")
        #expect(resolverInvokeCount.value == 0, "isAvailable must not call the resolver")
        #expect(spy.readCount == 0, "spy store must not be read during isAvailable")
    }

    @Test("isAvailable returns false when neither resolver nor static key")
    func isAvailableFalseWhenNeitherResolverNorKey() async {
        let config = AnthropicProvider.Configuration(apiKey: "")
        let provider = AnthropicProvider(configuration: config)
        let available = await provider.isAvailable
        #expect(available == false)
    }
}
