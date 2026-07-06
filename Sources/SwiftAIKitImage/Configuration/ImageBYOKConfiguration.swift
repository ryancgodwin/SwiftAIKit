import Foundation

/// Names and defaults for a bring-your-own-key image-provider setup. Shared by
/// `ImageProviderConfigurator` (and any future readiness/settings UI) so key
/// strings and defaults are defined exactly once.
///
/// Mirrors `SwiftAIKit.BYOKConfiguration`, extended to cover two providers
/// (Gemini and OpenAI image) instead of one.
public struct ImageBYOKConfiguration: Sendable {

    /// UserDefaults key under which the active image provider is persisted (the
    /// router's `defaultsKey`).
    public let providerDefaultsKey: String

    /// Keychain account name for the Gemini image API key.
    public let geminiAPIKeyAccount: String

    /// UserDefaults key for the Gemini image endpoint override.
    public let geminiEndpointDefaultsKey: String

    /// UserDefaults key for the Gemini image model override.
    public let geminiModelDefaultsKey: String

    /// Endpoint used for Gemini image generation when no override is stored.
    public let geminiDefaultEndpoint: String

    /// Model used for Gemini image generation when no override is stored.
    ///
    /// Verify against https://ai.google.dev/gemini-api/docs/models before relying on this
    /// default — provider model IDs move fast. Centralized here (rather than hardcoded in
    /// `GeminiImageProvider.Configuration`) so it is changed in exactly one place.
    public let geminiDefaultModel: String

    /// Keychain account name for the OpenAI image API key.
    public let openAIAPIKeyAccount: String

    /// UserDefaults key for the OpenAI image endpoint override.
    public let openAIEndpointDefaultsKey: String

    /// UserDefaults key for the OpenAI image model override.
    public let openAIModelDefaultsKey: String

    /// Endpoint used for OpenAI image generation when no override is stored.
    public let openAIDefaultEndpoint: String

    /// Model used for OpenAI image generation when no override is stored.
    ///
    /// Verify against https://developers.openai.com/api/docs/deprecations before relying on this
    /// default — provider model IDs move fast. As of 2026-07-06, `gpt-image-1` itself does NOT
    /// appear on OpenAI's deprecations page and is not scheduled for shutdown; only the newer
    /// `gpt-image-1-mini` and `gpt-image-1.5` variants are (2026-12-01), migrating to the
    /// token-billed `gpt-image-2`. `gpt-image-1` remains the mainline per-image-billed model and
    /// is kept as the default here. Re-check the deprecations page periodically, since OpenAI's
    /// model lineup moves fast. Centralized here (rather than hardcoded in
    /// `OpenAIImageProvider.Configuration`) so it is changed in exactly one place.
    public let openAIDefaultModel: String

    public init(
        providerDefaultsKey: String = "aiImageProvider",
        geminiAPIKeyAccount: String = "geminiImageAPIKey",
        geminiEndpointDefaultsKey: String = "geminiImageEndpoint",
        geminiModelDefaultsKey: String = "geminiImageModel",
        geminiDefaultEndpoint: String = "https://generativelanguage.googleapis.com",
        geminiDefaultModel: String = "gemini-3.1-flash-lite-image",
        openAIAPIKeyAccount: String = "openAIImageAPIKey",
        openAIEndpointDefaultsKey: String = "openAIImageEndpoint",
        openAIModelDefaultsKey: String = "openAIImageModel",
        openAIDefaultEndpoint: String = "https://api.openai.com",
        openAIDefaultModel: String = "gpt-image-1"
    ) {
        self.providerDefaultsKey = providerDefaultsKey
        self.geminiAPIKeyAccount = geminiAPIKeyAccount
        self.geminiEndpointDefaultsKey = geminiEndpointDefaultsKey
        self.geminiModelDefaultsKey = geminiModelDefaultsKey
        self.geminiDefaultEndpoint = geminiDefaultEndpoint
        self.geminiDefaultModel = geminiDefaultModel
        self.openAIAPIKeyAccount = openAIAPIKeyAccount
        self.openAIEndpointDefaultsKey = openAIEndpointDefaultsKey
        self.openAIModelDefaultsKey = openAIModelDefaultsKey
        self.openAIDefaultEndpoint = openAIDefaultEndpoint
        self.openAIDefaultModel = openAIDefaultModel
    }

    /// The conventional configuration.
    public static let `default` = ImageBYOKConfiguration()
}
