/// Names and defaults for a bring-your-own-key Anthropic setup. Shared by
/// `ProviderReadinessChecker` and the `SwiftAIKitUI` settings view so key
/// strings and defaults are defined exactly once.
public struct BYOKConfiguration: Sendable {

    /// UserDefaults key under which the active provider is persisted (the
    /// router's `defaultsKey`).
    public let providerDefaultsKey: String

    /// Keychain account name for the Anthropic API key.
    public let apiKeyAccount: String

    /// UserDefaults key for the Anthropic endpoint override.
    public let endpointDefaultsKey: String

    /// UserDefaults key for the Anthropic model override.
    public let modelDefaultsKey: String

    /// Endpoint used when no override is stored.
    public let defaultEndpoint: String

    /// Model used when no override is stored.
    public let defaultModel: String

    public init(
        providerDefaultsKey: String = "aiProvider",
        apiKeyAccount: String = "anthropicAPIKey",
        endpointDefaultsKey: String = "anthropicEndpoint",
        modelDefaultsKey: String = "anthropicModel",
        defaultEndpoint: String = "https://api.anthropic.com",
        defaultModel: String = "claude-sonnet-4-20250514"
    ) {
        self.providerDefaultsKey = providerDefaultsKey
        self.apiKeyAccount = apiKeyAccount
        self.endpointDefaultsKey = endpointDefaultsKey
        self.modelDefaultsKey = modelDefaultsKey
        self.defaultEndpoint = defaultEndpoint
        self.defaultModel = defaultModel
    }

    /// The conventional configuration (matches DiagramDesigner's historical keys).
    public static let `default` = BYOKConfiguration()
}
