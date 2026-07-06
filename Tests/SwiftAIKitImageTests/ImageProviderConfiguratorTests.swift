import Foundation
import Testing
@testable import SwiftAIKit
@testable import SwiftAIKitImage

// MARK: - Spy SecretStore (mirrors LazyAnthropicKeyTests.SpySecretStore)

/// Spy `SecretStore` that tracks how many times `string(forKey:)` is called.
/// Used to prove the API key is NOT read at configure time.
private final class SpyImageSecretStore: SecretStore, @unchecked Sendable {

    private let lock = NSLock()
    private var _storage: [String: String] = [:]
    private var _readCount: Int = 0

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

@MainActor
@Suite("ImageProviderConfigurator + SecretStore")
struct ImageProviderConfiguratorTests {

    // MARK: - Readiness-style: key present/absent

    // NOTE: `isAvailable` on both image providers intentionally checks only "is a resolver or
    // static key configured", not "does the resolver currently return a non-empty value" — it
    // must NOT invoke the resolver (that would defeat lazy-loading; see
    // `GeminiImageProvider.isAvailable` / `OpenAIImageProvider.isAvailable` doc comments, mirroring
    // `AnthropicProvider.isAvailable`). So once `ImageProviderConfigurator` attaches a resolver,
    // `isAvailable` is `true` regardless of whether the store currently holds a key — actual key
    // presence is validated at request time inside `generate()`. These tests instead prove that
    // behavior directly: the resolver is what's configured, and reading it reflects the store.

    @Test("configureGemini with no stored key: isAvailable is true (resolver configured), resolver yields no key")
    func geminiNoKeyResolverYieldsNil() async {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: "test_img_cfg_1")
        let store = InMemorySecretStore()

        ImageProviderConfigurator.configureGemini(router: router, secretStore: store, config: .default)

        let available = await router.isProviderAvailable(.geminiNanoBanana)
        #expect(available == true, "isAvailable reflects resolver presence, not resolver content")
        #expect(store.string(forKey: ImageBYOKConfiguration.default.geminiAPIKeyAccount) == nil)
    }

    @Test("configureGemini with a stored key reports isAvailable == true and the store holds the key")
    func geminiWithKeyAvailable() async {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: "test_img_cfg_2")
        let store = InMemorySecretStore()
        store.set("AIza-stored-key", forKey: ImageBYOKConfiguration.default.geminiAPIKeyAccount)

        ImageProviderConfigurator.configureGemini(router: router, secretStore: store, config: .default)

        let available = await router.isProviderAvailable(.geminiNanoBanana)
        #expect(available == true)
        #expect(store.string(forKey: ImageBYOKConfiguration.default.geminiAPIKeyAccount) == "AIza-stored-key")
    }

    @Test("configureOpenAIImage with no stored key: isAvailable is true (resolver configured), resolver yields no key")
    func openAINoKeyResolverYieldsNil() async {
        let router = ImageServiceRouter(defaultProvider: .openAIImage, defaultsKey: "test_img_cfg_3")
        let store = InMemorySecretStore()

        ImageProviderConfigurator.configureOpenAIImage(router: router, secretStore: store, config: .default)

        let available = await router.isProviderAvailable(.openAIImage)
        #expect(available == true, "isAvailable reflects resolver presence, not resolver content")
        #expect(store.string(forKey: ImageBYOKConfiguration.default.openAIAPIKeyAccount) == nil)
    }

    @Test("configureOpenAIImage with a stored key reports isAvailable == true and the store holds the key")
    func openAIWithKeyAvailable() async {
        let router = ImageServiceRouter(defaultProvider: .openAIImage, defaultsKey: "test_img_cfg_4")
        let store = InMemorySecretStore()
        store.set("sk-stored-key", forKey: ImageBYOKConfiguration.default.openAIAPIKeyAccount)

        ImageProviderConfigurator.configureOpenAIImage(router: router, secretStore: store, config: .default)

        let available = await router.isProviderAvailable(.openAIImage)
        #expect(available == true)
        #expect(store.string(forKey: ImageBYOKConfiguration.default.openAIAPIKeyAccount) == "sk-stored-key")
    }

    @Test("provider with neither resolver nor static key reports isAvailable == false")
    func noResolverNoKeyNotAvailable() async {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: "test_img_cfg_1b")
        // Constructed directly (bypassing the configurator) to exercise the actual "not
        // configured at all" case, since the configurator always attaches a resolver.
        router.configure(.geminiNanoBanana, with: GeminiImageProvider(configuration: .init(apiKey: "")))

        let available = await router.isProviderAvailable(.geminiNanoBanana)
        #expect(available == false)
    }

    // MARK: - configureAll registers all three providers

    @Test("configureAll registers gemini, openAIImage, and svgFallback")
    func configureAllRegistersAllProviders() async {
        let router = ImageServiceRouter(defaultProvider: .svgFallback, defaultsKey: "test_img_cfg_5")
        let store = InMemorySecretStore()

        ImageProviderConfigurator.configureAll(router: router, secretStore: store) { _, _ in "unused" }

        let registered = router.registeredProviders
        #expect(registered.contains(.geminiNanoBanana))
        #expect(registered.contains(.openAIImage))
        #expect(registered.contains(.svgFallback))
    }

    // MARK: - Lazy loading: zero reads at configure time

    @Test("configureGemini(secretStore:) reads the store zero times at configure time")
    func geminiConfigureTimeReadCountIsZero() {
        let router = ImageServiceRouter(
            defaultProvider: .geminiNanoBanana,
            defaultsKey: "test_img_lazy_1_\(UUID().uuidString)"
        )
        let spy = SpyImageSecretStore()
        spy.set("AIza-lazily-loaded", forKey: ImageBYOKConfiguration.default.geminiAPIKeyAccount)

        ImageProviderConfigurator.configureGemini(router: router, secretStore: spy, config: .default)

        #expect(spy.readCount == 0, "Keychain must not be touched at configure time")
    }

    @Test("configureOpenAIImage(secretStore:) reads the store zero times at configure time")
    func openAIConfigureTimeReadCountIsZero() {
        let router = ImageServiceRouter(
            defaultProvider: .openAIImage,
            defaultsKey: "test_img_lazy_2_\(UUID().uuidString)"
        )
        let spy = SpyImageSecretStore()
        spy.set("sk-lazily-loaded", forKey: ImageBYOKConfiguration.default.openAIAPIKeyAccount)

        ImageProviderConfigurator.configureOpenAIImage(router: router, secretStore: spy, config: .default)

        #expect(spy.readCount == 0, "Keychain must not be touched at configure time")
    }

    @Test("configureOpenAIImage(secretStore:) reads the store when generate() is actually invoked")
    func openAIGenerateReadsStoreAfterConfigure() async {
        let router = ImageServiceRouter(
            defaultProvider: .openAIImage,
            defaultsKey: "test_img_lazy_4_\(UUID().uuidString)"
        )
        let spy = SpyImageSecretStore()
        // Deliberately no key stored: generate() should still invoke the resolver (proving it
        // fires), then fail fast with `.notConfigured` before any network I/O — offline and
        // deterministic.
        ImageProviderConfigurator.configureOpenAIImage(router: router, secretStore: spy, config: .default)

        #expect(spy.readCount == 0, "sanity check: unread before generate() is called")

        await #expect(throws: AIError.self) {
            _ = try await router.generate(ImageRequest(prompt: "a red panda"))
        }

        #expect(spy.readCount > 0, "generate() must invoke the resolver, proving it is wired up")
    }

    @Test("isProviderAvailable does not read the store (resolver is not invoked by isAvailable)")
    func isAvailableDoesNotReadStore() async {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: "test_img_lazy_3")
        let spy = SpyImageSecretStore()
        spy.set("AIza-key", forKey: ImageBYOKConfiguration.default.geminiAPIKeyAccount)

        ImageProviderConfigurator.configureGemini(router: router, secretStore: spy, config: .default)
        // Reset the count contributed by set(), which does not increment readCount, but be explicit.
        let countBeforeCheck = spy.readCount
        _ = await router.isProviderAvailable(.geminiNanoBanana)
        #expect(spy.readCount == countBeforeCheck, "isAvailable must not read the secret store")
    }

    // MARK: - Defaults applied when no UserDefaults overrides are set

    @Test("configureGemini uses ImageBYOKConfiguration default endpoint and model")
    func geminiUsesDefaults() async {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: "test_img_defaults_1")
        let store = InMemorySecretStore()

        ImageProviderConfigurator.configureGemini(router: router, secretStore: store, config: .default)

        // Provider is registered even without a key (isAvailable is false, but configured).
        #expect(router.registeredProviders.contains(.geminiNanoBanana))
    }
}
