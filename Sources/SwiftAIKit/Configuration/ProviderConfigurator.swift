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
            .flatMap { $0.isEmpty ? nil : $0 } ?? "claude-sonnet-4-6"

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
        model: String = "claude-sonnet-4-6",
        session: URLSession = .shared
    ) {
        router.configure(.anthropic, with: AnthropicProvider(
            configuration: .init(apiKey: apiKey, endpoint: endpoint, model: model),
            session: session
        ))
    }

    /// Configure the Anthropic provider, reading the API key from a `SecretStore`
    /// (the secure path) and the endpoint/model overrides from UserDefaults.
    ///
    /// The API key is loaded **lazily** — it is NOT read from the store here.
    /// Instead, a `@Sendable` closure capturing the store is handed to
    /// `AnthropicProvider.Configuration.apiKeyResolver`. The key is read only
    /// when `AnthropicProvider.complete()` is actually called, so macOS will
    /// not show a Keychain password prompt at app launch when the user is only
    /// using on-device AI. Endpoint and model may still be read from
    /// `UserDefaults` at configure time (those do not trigger any OS prompt).
    @MainActor
    public static func configureAnthropic(
        router: AIServiceRouter,
        secretStore: SecretStore,
        config: BYOKConfiguration = .default,
        session: URLSession = .shared
    ) {
        let endpoint = UserDefaults.standard.string(forKey: config.endpointDefaultsKey) ?? ""
        let model = UserDefaults.standard.string(forKey: config.modelDefaultsKey) ?? ""
        let configuration = AnthropicProvider.Configuration(
            apiKey: "",
            endpoint: endpoint.isEmpty ? config.defaultEndpoint : endpoint,
            model: model.isEmpty ? config.defaultModel : model,
            // Lazy resolver: Keychain is read only when a request is made.
            apiKeyResolver: { [secretStore] in secretStore.string(forKey: config.apiKeyAccount) }
        )
        router.configure(.anthropic, with: AnthropicProvider(
            configuration: configuration,
            session: session
        ))
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
