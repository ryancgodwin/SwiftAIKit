import Foundation
import SwiftAIKit

/// Convenience factory for creating and registering image providers from a `SecretStore` and
/// `UserDefaults`-stored overrides.
///
/// Mirrors `SwiftAIKit.ProviderConfigurator`'s lazy-key pattern: the API key is read from the
/// `SecretStore` only when a request is actually made (via `Configuration.apiKeyResolver`), never
/// at configure time. This avoids triggering a Keychain password prompt at app launch when the
/// user never ends up using cloud image generation.
///
/// Usage:
/// ```swift
/// let router = ImageServiceRouter()
/// ImageProviderConfigurator.configureAll(
///     router: router,
///     secretStore: KeychainSecretStore(service: "com.myapp"),
///     svgFallbackComplete: { prompt, systemPrompt in
///         try await aiRouter.complete(prompt, systemPrompt: systemPrompt).content
///     }
/// )
/// ```
public enum ImageProviderConfigurator {

    // MARK: - Full Setup

    /// Configure all available image providers (Gemini, OpenAI image, SVG fallback) on the
    /// router from a `SecretStore` and `UserDefaults` overrides.
    ///
    /// - Parameters:
    ///   - router: The router to configure.
    ///   - secretStore: The secret store backing both providers' API keys.
    ///   - config: Keychain account names, UserDefaults keys, and defaults. Defaults to
    ///     `.default`.
    ///   - session: Optional `URLSession` for network requests. Defaults to `URLSession.shared`.
    ///   - svgFallbackComplete: Text-completion shim passed to `SVGFallbackProvider`. See that
    ///     type's initializer for details.
    @MainActor
    public static func configureAll(
        router: ImageServiceRouter,
        secretStore: SecretStore,
        config: ImageBYOKConfiguration = .default,
        session: URLSession = .shared,
        svgFallbackComplete: @escaping @Sendable (_ prompt: String, _ systemPrompt: String?) async throws -> String
    ) {
        configureGemini(router: router, secretStore: secretStore, config: config, session: session)
        configureOpenAIImage(router: router, secretStore: secretStore, config: config, session: session)
        router.configure(.svgFallback, with: SVGFallbackProvider(complete: svgFallbackComplete))
    }

    // MARK: - Individual Provider Setup

    /// Configure just the Gemini image provider, reading the API key from a `SecretStore` (the
    /// secure path) and the endpoint/model overrides from `UserDefaults`.
    ///
    /// The API key is loaded **lazily** — it is NOT read from the store here. Instead, a
    /// `@Sendable` closure capturing the store is handed to
    /// `GeminiImageProvider.Configuration.apiKeyResolver`. The key is read only when
    /// `GeminiImageProvider.generate()` is actually called.
    @MainActor
    public static func configureGemini(
        router: ImageServiceRouter,
        secretStore: SecretStore,
        config: ImageBYOKConfiguration = .default,
        session: URLSession = .shared
    ) {
        let endpoint = UserDefaults.standard.string(forKey: config.geminiEndpointDefaultsKey) ?? ""
        let model = UserDefaults.standard.string(forKey: config.geminiModelDefaultsKey) ?? ""
        let configuration = GeminiImageProvider.Configuration(
            apiKey: "",
            endpoint: endpoint.isEmpty ? config.geminiDefaultEndpoint : endpoint,
            model: model.isEmpty ? config.geminiDefaultModel : model,
            // Lazy resolver: Keychain is read only when a request is made.
            apiKeyResolver: { [secretStore] in secretStore.string(forKey: config.geminiAPIKeyAccount) }
        )
        router.configure(.geminiNanoBanana, with: GeminiImageProvider(configuration: configuration, session: session))
    }

    /// Configure just the OpenAI image provider, reading the API key from a `SecretStore` (the
    /// secure path) and the endpoint/model overrides from `UserDefaults`.
    ///
    /// The API key is loaded **lazily** — see `configureGemini(router:secretStore:config:session:)`
    /// for the full rationale.
    @MainActor
    public static func configureOpenAIImage(
        router: ImageServiceRouter,
        secretStore: SecretStore,
        config: ImageBYOKConfiguration = .default,
        session: URLSession = .shared
    ) {
        let endpoint = UserDefaults.standard.string(forKey: config.openAIEndpointDefaultsKey) ?? ""
        let model = UserDefaults.standard.string(forKey: config.openAIModelDefaultsKey) ?? ""
        let configuration = OpenAIImageProvider.Configuration(
            apiKey: "",
            endpoint: endpoint.isEmpty ? config.openAIDefaultEndpoint : endpoint,
            model: model.isEmpty ? config.openAIDefaultModel : model,
            // Lazy resolver: Keychain is read only when a request is made.
            apiKeyResolver: { [secretStore] in secretStore.string(forKey: config.openAIAPIKeyAccount) }
        )
        router.configure(.openAIImage, with: OpenAIImageProvider(configuration: configuration, session: session))
    }
}
