import Foundation
import Testing
@testable import SwiftAIKitImage
import SwiftAIKit

/// A stub image provider whose availability, result, and error are all configurable,
/// so tests can drive the router through the active-provider, fallback, and
/// no-fallback-succeeds paths.
actor StubImageProvider: ImageServiceProtocol {
    let providerType: ImageProviderType
    var isAvailable: Bool
    var result: ImageResult?
    var error: AIError?
    private(set) var generateCallCount = 0

    init(
        providerType: ImageProviderType,
        isAvailable: Bool = true,
        result: ImageResult? = nil,
        error: AIError? = nil
    ) {
        self.providerType = providerType
        self.isAvailable = isAvailable
        self.result = result
        self.error = error
    }

    func generate(_ request: ImageRequest) async throws -> ImageResult {
        generateCallCount += 1
        if let error {
            throw error
        }
        if let result {
            return result
        }
        return ImageResult(data: Data(), mimeType: "image/png", provider: providerType)
    }
}

@Suite("ImageServiceRouter Tests")
@MainActor
struct ImageServiceRouterTests {

    /// Generates a unique UserDefaults key per test so state doesn't leak across tests
    /// (the router persists to `UserDefaults.standard`, mirroring `AIServiceRouter`).
    private func uniqueDefaultsKey(_ name: String = #function) -> String {
        "test_imageProvider_\(name)_\(UUID().uuidString)"
    }

    @Test("generate() uses the active provider when available")
    func activeProviderPath() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let expected = ImageResult(data: Data([0x01]), mimeType: "image/png", provider: .geminiNanoBanana)
        let stub = StubImageProvider(providerType: .geminiNanoBanana, isAvailable: true, result: expected)
        router.configure(.geminiNanoBanana, with: stub)

        let result = try await router.generate(ImageRequest(prompt: "a red panda"))

        #expect(result.data == expected.data)
        #expect(result.provider == .geminiNanoBanana)
        #expect(await stub.generateCallCount == 1)
    }

    @Test("generate() falls back when the active provider reports isAvailable == false")
    func fallbackOnUnavailable() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let unavailable = StubImageProvider(providerType: .geminiNanoBanana, isAvailable: false)
        let fallbackResult = ImageResult(data: Data([0x02]), mimeType: "image/svg+xml", provider: .svgFallback)
        let fallback = StubImageProvider(providerType: .svgFallback, isAvailable: true, result: fallbackResult)

        router.configure(.geminiNanoBanana, with: unavailable)
        router.configure(.svgFallback, with: fallback)
        router.fallbackOrder = [.geminiNanoBanana, .svgFallback]

        let result = try await router.generate(ImageRequest(prompt: "a red panda"))

        #expect(result.provider == .svgFallback)
        #expect(result.data == fallbackResult.data)
        #expect(await unavailable.generateCallCount == 0)
        #expect(await fallback.generateCallCount == 1)
    }

    @Test("generate() falls back when the active provider throws providerUnavailable")
    func fallbackOnThrownProviderUnavailable() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let failing = StubImageProvider(
            providerType: .geminiNanoBanana,
            isAvailable: true,
            error: .providerUnavailable("no credentials")
        )
        let fallbackResult = ImageResult(data: Data([0x03]), mimeType: "image/svg+xml", provider: .svgFallback)
        let fallback = StubImageProvider(providerType: .svgFallback, isAvailable: true, result: fallbackResult)

        router.configure(.geminiNanoBanana, with: failing)
        router.configure(.svgFallback, with: fallback)
        router.fallbackOrder = [.geminiNanoBanana, .svgFallback]

        let result = try await router.generate(ImageRequest(prompt: "a red panda"))

        #expect(result.provider == .svgFallback)
        #expect(await fallback.generateCallCount == 1)
    }

    @Test("generate() falls back when the active provider throws notConfigured")
    func fallbackOnThrownNotConfigured() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let failing = StubImageProvider(
            providerType: .geminiNanoBanana,
            isAvailable: true,
            error: .notConfigured("missing API key")
        )
        let fallbackResult = ImageResult(data: Data([0x04]), mimeType: "image/svg+xml", provider: .svgFallback)
        let fallback = StubImageProvider(providerType: .svgFallback, isAvailable: true, result: fallbackResult)

        router.configure(.geminiNanoBanana, with: failing)
        router.configure(.svgFallback, with: fallback)
        router.fallbackOrder = [.geminiNanoBanana, .svgFallback]

        let result = try await router.generate(ImageRequest(prompt: "a red panda"))

        #expect(result.provider == .svgFallback)
    }

    @Test("generate() does not fall back on requestFailed (non-fallback error)")
    func noFallbackForRequestFailed() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let failing = StubImageProvider(
            providerType: .geminiNanoBanana,
            isAvailable: true,
            error: .requestFailed("network error")
        )
        let fallback = StubImageProvider(providerType: .svgFallback, isAvailable: true)

        router.configure(.geminiNanoBanana, with: failing)
        router.configure(.svgFallback, with: fallback)
        router.fallbackOrder = [.geminiNanoBanana, .svgFallback]

        await #expect(throws: AIError.self) {
            try await router.generate(ImageRequest(prompt: "a red panda"))
        }
        #expect(await fallback.generateCallCount == 0)
    }

    @Test("generate() rethrows the original error when no fallback succeeds")
    func rethrowsWhenNoFallbackSucceeds() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let failing = StubImageProvider(providerType: .geminiNanoBanana, isAvailable: false)
        let alsoUnavailable = StubImageProvider(providerType: .svgFallback, isAvailable: false)

        router.configure(.geminiNanoBanana, with: failing)
        router.configure(.svgFallback, with: alsoUnavailable)
        router.fallbackOrder = [.geminiNanoBanana, .svgFallback]

        await #expect(throws: AIError.self) {
            try await router.generate(ImageRequest(prompt: "a red panda"))
        }
    }

    @Test("generate() throws notConfigured when the active provider is unregistered")
    func throwsWhenUnregistered() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())

        await #expect(throws: AIError.self) {
            try await router.generate(ImageRequest(prompt: "a red panda"))
        }
    }

    @Test("generate(using:_:) targets a specific provider with no fallback")
    func generateUsingTargetsSpecificProvider() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let active = StubImageProvider(providerType: .geminiNanoBanana, isAvailable: true)
        let other = StubImageProvider(
            providerType: .svgFallback,
            isAvailable: true,
            result: ImageResult(data: Data([0x05]), mimeType: "image/svg+xml", provider: .svgFallback)
        )
        router.configure(.geminiNanoBanana, with: active)
        router.configure(.svgFallback, with: other)
        router.fallbackOrder = [.geminiNanoBanana]

        let result = try await router.generate(using: .svgFallback, ImageRequest(prompt: "a diagram"))

        #expect(result.provider == .svgFallback)
        #expect(await active.generateCallCount == 0)
    }

    @Test("generate(using:_:) does not fall back when the targeted provider fails")
    func generateUsingDoesNotFallBack() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let targeted = StubImageProvider(
            providerType: .svgFallback,
            isAvailable: false,
            error: .providerUnavailable("not ready")
        )
        let fallback = StubImageProvider(providerType: .geminiNanoBanana, isAvailable: true)
        router.configure(.svgFallback, with: targeted)
        router.configure(.geminiNanoBanana, with: fallback)
        router.fallbackOrder = [.geminiNanoBanana]

        await #expect(throws: AIError.self) {
            try await router.generate(using: .svgFallback, ImageRequest(prompt: "a diagram"))
        }
        #expect(await fallback.generateCallCount == 0)
    }

    @Test("generate(using:_:) throws notConfigured for an unregistered provider")
    func generateUsingThrowsForUnregistered() async throws {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())

        await #expect(throws: AIError.self) {
            try await router.generate(using: .openAIImage, ImageRequest(prompt: "a diagram"))
        }
    }

    @Test("configure(_:with:) registers a provider and it becomes visible in registeredProviders")
    func configureRegistersProvider() {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let stub = StubImageProvider(providerType: .geminiNanoBanana)
        router.configure(.geminiNanoBanana, with: stub)

        #expect(router.registeredProviders == [.geminiNanoBanana])
        #expect(router.activeProvider != nil)
    }

    @Test("removeProvider(_:) removes a registered provider")
    func removeProviderRemovesRegistration() {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let stub = StubImageProvider(providerType: .geminiNanoBanana)
        router.configure(.geminiNanoBanana, with: stub)
        router.removeProvider(.geminiNanoBanana)

        #expect(router.registeredProviders.isEmpty)
        #expect(router.activeProvider == nil)
    }

    @Test("activeProviderType persists to UserDefaults under the given key")
    func activeProviderPersistsToUserDefaults() {
        let key = uniqueDefaultsKey()
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: key)
        router.activeProviderType = .svgFallback

        #expect(UserDefaults.standard.string(forKey: key) == ImageProviderType.svgFallback.rawValue)

        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test("init reads a previously saved provider from UserDefaults")
    func initReadsSavedProvider() {
        let key = uniqueDefaultsKey()
        UserDefaults.standard.set(ImageProviderType.openAIImage.rawValue, forKey: key)

        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: key)

        #expect(router.activeProviderType == .openAIImage)

        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test("isProviderAvailable returns false for an unregistered provider")
    func isProviderAvailableFalseWhenUnregistered() async {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        let available = await router.isProviderAvailable(.geminiNanoBanana)
        #expect(available == false)
    }

    @Test("isProviderAvailable reflects the provider's isAvailable state")
    func isProviderAvailableReflectsState() async {
        let router = ImageServiceRouter(defaultProvider: .geminiNanoBanana, defaultsKey: uniqueDefaultsKey())
        router.configure(.geminiNanoBanana, with: StubImageProvider(providerType: .geminiNanoBanana, isAvailable: true))
        let available = await router.isProviderAvailable(.geminiNanoBanana)
        #expect(available == true)
    }
}
