import Foundation

/// Routes AI requests to the active provider.
///
/// The router is the main entry point for consuming apps. It manages provider
/// instances, handles switching between providers, and provides a single
/// `complete()` method that delegates to the active provider.
///
/// Usage:
/// ```swift
/// let router = AIServiceRouter()
///
/// // Configure providers
/// router.configure(.anthropic, with: AnthropicProvider(
///     configuration: .init(apiKey: "sk-ant-...")
/// ))
/// router.configure(.openAI, with: OpenAIProvider(
///     configuration: .init(apiKey: "sk-...", endpoint: "http://localhost:11434", model: "llama3")
/// ))
/// router.configure(.onDevice, with: OnDeviceProvider())
///
/// // Set active provider
/// router.activeProviderType = .anthropic
///
/// // Use it
/// let response = try await router.complete(
///     messages: [AIMessage(role: .user, content: "Hello")],
///     systemPrompt: "You are helpful.",
///     maxTokens: 1024
/// )
/// ```
@MainActor
@Observable
public final class AIServiceRouter {

    // MARK: - State

    /// The currently active provider type.
    public var activeProviderType: AIProviderType {
        didSet {
            UserDefaults.standard.set(activeProviderType.rawValue, forKey: providerDefaultsKey)
        }
    }

    /// All registered providers.
    private var providers: [AIProviderType: any AIServiceProtocol] = [:]

    /// UserDefaults key for persisting the active provider choice.
    private let providerDefaultsKey: String

    /// Ordered list of provider types to try when the active provider is unavailable.
    /// Set this to enable automatic fallback (e.g., `[.anthropic, .openAI]`).
    public var fallbackOrder: [AIProviderType] = []

    // MARK: - Init

    /// Creates a new router.
    ///
    /// - Parameters:
    ///   - defaultProvider: The provider to use if no saved preference exists.
    ///   - defaultsKey: The UserDefaults key for persisting the provider choice.
    ///     Use different keys if multiple routers exist in the same app.
    public init(
        defaultProvider: AIProviderType = .onDevice,
        defaultsKey: String = "swiftaikit_activeProvider"
    ) {
        self.providerDefaultsKey = defaultsKey
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        self.activeProviderType = saved.flatMap(AIProviderType.init(rawValue:)) ?? defaultProvider
    }

    // MARK: - Provider Management

    /// Register a provider instance for a given type.
    public func configure(_ type: AIProviderType, with provider: any AIServiceProtocol) {
        providers[type] = provider
    }

    /// Remove a provider registration.
    public func removeProvider(_ type: AIProviderType) {
        providers.removeValue(forKey: type)
    }

    /// The currently active provider instance, if registered.
    public var activeProvider: (any AIServiceProtocol)? {
        providers[activeProviderType]
    }

    /// All registered provider types.
    public var registeredProviders: [AIProviderType] {
        Array(providers.keys).sorted { $0.rawValue < $1.rawValue }
    }

    /// Check if a specific provider is available and configured.
    public func isProviderAvailable(_ type: AIProviderType) async -> Bool {
        guard let provider = providers[type] else { return false }
        return await provider.isAvailable
    }

    // MARK: - Completion

    /// Send a completion request to the active provider.
    ///
    /// - Parameters:
    ///   - messages: The conversation messages.
    ///   - systemPrompt: An optional system prompt.
    ///   - maxTokens: Maximum tokens to generate. Defaults to 4096.
    /// - Returns: The AI response.
    /// - Throws: `AIError.notConfigured` if no provider is active,
    ///           or any `AIError` from the underlying provider.
    public func complete(
        messages: [AIMessage],
        systemPrompt: String? = nil,
        maxTokens: Int = 4096
    ) async throws -> AIResponse {
        guard let provider = activeProvider else {
            throw AIError.notConfigured(
                "No provider configured for \(activeProviderType.displayName)."
            )
        }

        // Try the active provider first.
        do {
            return try await provider.complete(
                messages: messages,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens
            )
        } catch let error as AIError where shouldFallback(for: error) {
            // Active provider unavailable — try fallbacks in order.
            for fallbackType in fallbackOrder where fallbackType != activeProviderType {
                guard let fallback = providers[fallbackType],
                      await fallback.isAvailable else { continue }
                return try await fallback.complete(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens
                )
            }
            // No fallback succeeded — rethrow the original error.
            throw error
        }
    }

    /// Determines whether a failed request should trigger fallback to another provider.
    private func shouldFallback(for error: AIError) -> Bool {
        switch error {
        case .providerUnavailable, .notConfigured:
            return true
        case .requestFailed, .invalidResponse, .contentFiltered:
            return false
        }
    }

    /// Send a completion request to a specific provider (regardless of active selection).
    ///
    /// Useful for one-off requests to a different provider without switching the active selection.
    public func complete(
        using providerType: AIProviderType,
        messages: [AIMessage],
        systemPrompt: String? = nil,
        maxTokens: Int = 4096
    ) async throws -> AIResponse {
        guard let provider = providers[providerType] else {
            throw AIError.notConfigured(
                "No provider configured for \(providerType.displayName)."
            )
        }

        return try await provider.complete(
            messages: messages,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens
        )
    }
}
