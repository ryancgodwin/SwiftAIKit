import Foundation

/// Convenience factory for creating and registering providers from UserDefaults-stored credentials.
///
/// This helper reads API keys and endpoints from UserDefaults and configures
/// the router with the appropriate providers. Apps can use this to set up
/// providers at launch without writing boilerplate each time.
///
/// Usage:
/// ```swift
/// let router = AIServiceRouter()
/// ProviderConfigurator.configureAll(
///     router: router,
///     anthropicKeyDefault: "myApp_anthropicAPIKey",
///     openAIKeyDefault: "myApp_openAIAPIKey"
/// )
/// ```
public enum ProviderConfigurator {

    // MARK: - Full Setup

    /// Configure all available providers on the router from UserDefaults.
    ///
    /// - Parameters:
    ///   - router: The router to configure.
    ///   - session: Optional `URLSession` for network requests (e.g. with certificate pinning).
    ///     Defaults to `URLSession.shared`.
    ///   - anthropicKeyDefault: UserDefaults key for the Anthropic API key.
    ///   - anthropicEndpointDefault: UserDefaults key for the Anthropic endpoint.
    ///   - anthropicModelDefault: UserDefaults key for the Anthropic model.
    ///   - openAIKeyDefault: UserDefaults key for the OpenAI API key.
    ///   - openAIEndpointDefault: UserDefaults key for the OpenAI endpoint.
    ///   - openAIModelDefault: UserDefaults key for the OpenAI model.
    @MainActor
    public static func configureAll(
        router: AIServiceRouter,
        session: URLSession = .shared,
        anthropicKeyDefault: String = "swiftaikit_anthropicAPIKey",
        anthropicEndpointDefault: String = "swiftaikit_anthropicEndpoint",
        anthropicModelDefault: String = "swiftaikit_anthropicModel",
        openAIKeyDefault: String = "swiftaikit_openAIAPIKey",
        openAIEndpointDefault: String = "swiftaikit_openAIEndpoint",
        openAIModelDefault: String = "swiftaikit_openAIModel"
    ) {
        // On-Device — always register; availability is checked at runtime
        router.configure(.onDevice, with: OnDeviceProvider())

        // Anthropic
        let anthropicKey = UserDefaults.standard.string(forKey: anthropicKeyDefault) ?? ""
        let anthropicEndpoint = UserDefaults.standard.string(forKey: anthropicEndpointDefault)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "https://api.anthropic.com"
        let anthropicModel = UserDefaults.standard.string(forKey: anthropicModelDefault)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "claude-sonnet-4-20250514"

        router.configure(.anthropic, with: AnthropicProvider(
            configuration: .init(
                apiKey: anthropicKey,
                endpoint: anthropicEndpoint,
                model: anthropicModel
            ),
            session: session
        ))

        // OpenAI-Compatible
        let openAIKey = UserDefaults.standard.string(forKey: openAIKeyDefault) ?? ""
        let openAIEndpoint = UserDefaults.standard.string(forKey: openAIEndpointDefault)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "https://api.openai.com"
        let openAIModel = UserDefaults.standard.string(forKey: openAIModelDefault)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-4o"

        router.configure(.openAI, with: OpenAIProvider(
            configuration: .init(
                apiKey: openAIKey,
                endpoint: openAIEndpoint,
                model: openAIModel
            ),
            session: session
        ))
    }

    // MARK: - Individual Provider Setup

    /// Configure just the Anthropic provider.
    @MainActor
    public static func configureAnthropic(
        router: AIServiceRouter,
        apiKey: String,
        endpoint: String = "https://api.anthropic.com",
        model: String = "claude-sonnet-4-20250514",
        session: URLSession = .shared
    ) {
        router.configure(.anthropic, with: AnthropicProvider(
            configuration: .init(apiKey: apiKey, endpoint: endpoint, model: model),
            session: session
        ))
    }

    /// Configure the Anthropic provider, reading the API key from a `SecretStore`
    /// (the secure path) and the endpoint/model overrides from UserDefaults.
    @MainActor
    public static func configureAnthropic(
        router: AIServiceRouter,
        secretStore: SecretStore,
        config: BYOKConfiguration = .default,
        session: URLSession = .shared
    ) {
        let key = secretStore.string(forKey: config.apiKeyAccount) ?? ""
        let endpoint = UserDefaults.standard.string(forKey: config.endpointDefaultsKey) ?? ""
        let model = UserDefaults.standard.string(forKey: config.modelDefaultsKey) ?? ""
        configureAnthropic(
            router: router,
            apiKey: key,
            endpoint: endpoint.isEmpty ? config.defaultEndpoint : endpoint,
            model: model.isEmpty ? config.defaultModel : model,
            session: session
        )
    }

    /// Configure just the OpenAI-compatible provider.
    @MainActor
    public static func configureOpenAI(
        router: AIServiceRouter,
        apiKey: String,
        endpoint: String = "https://api.openai.com",
        model: String = "gpt-4o",
        session: URLSession = .shared
    ) {
        router.configure(.openAI, with: OpenAIProvider(
            configuration: .init(apiKey: apiKey, endpoint: endpoint, model: model),
            session: session
        ))
    }

    /// Configure just the on-device provider.
    @MainActor
    public static func configureOnDevice(router: AIServiceRouter) {
        router.configure(.onDevice, with: OnDeviceProvider())
    }
}
