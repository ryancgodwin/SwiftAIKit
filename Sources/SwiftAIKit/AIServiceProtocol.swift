import Foundation

/// Protocol that all AI service providers must conform to.
///
/// Each provider (Anthropic, OpenAI, On-Device) implements this protocol.
/// The consuming app provides the system prompt and messages; the provider
/// handles transport, authentication, and response parsing.
///
/// Providers are actors for thread safety. All methods are async and throw
/// `AIError` on failure.
public protocol AIServiceProtocol: Actor {

    /// The provider type this service implements.
    var providerType: AIProviderType { get }

    /// Whether this provider is currently available and configured.
    ///
    /// For on-device: checks hardware + model availability.
    /// For API providers: checks that credentials are configured (not that they're valid).
    var isAvailable: Bool { get }

    /// Send a completion request to the AI provider.
    ///
    /// - Parameters:
    ///   - messages: The conversation messages (user + assistant turns).
    ///   - systemPrompt: An optional system prompt prepended to the conversation.
    ///   - maxTokens: Maximum tokens to generate (provider may have its own caps).
    /// - Returns: The AI response with generated content and optional metadata.
    /// - Throws: `AIError` on failure.
    func complete(
        messages: [AIMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AIResponse
}
