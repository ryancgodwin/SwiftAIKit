import Foundation
import SwiftAIKit

/// Routes image-generation requests to the active provider.
///
/// The router is the main entry point for consuming apps. It manages provider
/// instances, handles switching between providers, and provides a single
/// `generate()` method that delegates to the active provider.
///
/// Usage:
/// ```swift
/// let router = ImageServiceRouter()
///
/// // Configure providers
/// router.configure(.geminiNanoBanana, with: GeminiImageProvider(apiKey: "..."))
/// router.configure(.svgFallback, with: SVGFallbackProvider())
///
/// // Set active provider
/// router.activeProviderType = .geminiNanoBanana
/// router.fallbackOrder = [.geminiNanoBanana, .svgFallback]
///
/// // Use it
/// let result = try await router.generate(ImageRequest(prompt: "a red panda"))
/// ```
@MainActor
@Observable
public final class ImageServiceRouter {

    // MARK: - State

    /// The currently active provider type.
    public var activeProviderType: ImageProviderType {
        didSet {
            UserDefaults.standard.set(activeProviderType.rawValue, forKey: providerDefaultsKey)
        }
    }

    /// All registered providers.
    private var providers: [ImageProviderType: any ImageServiceProtocol] = [:]

    /// UserDefaults key for persisting the active provider choice.
    private let providerDefaultsKey: String

    /// Ordered list of provider types to try when the active provider is unavailable.
    /// Set this to enable automatic fallback (e.g., `[.geminiNanoBanana, .svgFallback]`).
    public var fallbackOrder: [ImageProviderType] = []

    // MARK: - Init

    /// Creates a new router.
    ///
    /// - Parameters:
    ///   - defaultProvider: The provider to use if no saved preference exists.
    ///   - defaultsKey: The UserDefaults key for persisting the provider choice.
    ///     Use different keys if multiple routers exist in the same app.
    public init(
        defaultProvider: ImageProviderType = .svgFallback,
        defaultsKey: String = "swiftaikit_activeImageProvider"
    ) {
        self.providerDefaultsKey = defaultsKey
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        self.activeProviderType = saved.map(ImageProviderType.init(rawValue:)) ?? defaultProvider
    }

    // MARK: - Provider Management

    /// Register a provider instance for a given type.
    public func configure(_ type: ImageProviderType, with provider: any ImageServiceProtocol) {
        providers[type] = provider
    }

    /// Remove a provider registration.
    public func removeProvider(_ type: ImageProviderType) {
        providers.removeValue(forKey: type)
    }

    /// The currently active provider instance, if registered.
    public var activeProvider: (any ImageServiceProtocol)? {
        providers[activeProviderType]
    }

    /// All registered provider types.
    public var registeredProviders: [ImageProviderType] {
        Array(providers.keys).sorted { $0.rawValue < $1.rawValue }
    }

    /// Check if a specific provider is available and configured.
    public func isProviderAvailable(_ type: ImageProviderType) async -> Bool {
        guard let provider = providers[type] else { return false }
        return await provider.isAvailable
    }

    // MARK: - Generation

    /// Send a generation request to the active provider.
    ///
    /// - Parameter request: The image request.
    /// - Returns: The generated image result.
    /// - Throws: `AIError.notConfigured` if no provider is active,
    ///           or any `AIError` from the underlying provider.
    public func generate(_ request: ImageRequest) async throws -> ImageResult {
        guard let provider = activeProvider else {
            throw AIError.notConfigured(
                "No provider configured for \(activeProviderType.displayName)."
            )
        }

        // Try the active provider first.
        do {
            guard await provider.isAvailable else {
                throw AIError.providerUnavailable(
                    "Provider \(activeProviderType.displayName) is not available."
                )
            }
            return try await provider.generate(request)
        } catch let error as AIError where shouldFallback(for: error) {
            // Active provider unavailable — try fallbacks in order.
            //
            // NOTE: this intentionally diverges from `AIServiceRouter`'s (core, text-completion)
            // fallback walk, which aborts the whole chain the instant any candidate's
            // `generate()`/`complete()` throws. Here, a THROWING candidate (e.g. registered but
            // missing credentials, so it throws `.notConfigured` instead of failing the cheaper
            // `isAvailable` pre-check) does not abort the walk — we catch fallback-eligible
            // errors from `generate()` itself and `continue` to the next candidate, so a chain
            // like `[.geminiNanoBanana, .openAIImage, .svgFallback]` still reaches
            // `.svgFallback` even if `.openAIImage` is registered-but-unconfigured. This matches
            // the image router's "guarantee a result" intent (the chain typically terminates in
            // `SVGFallbackProvider`, which is unconditionally available). Non-eligible errors
            // (e.g. `.requestFailed`, `.contentFiltered`) still propagate immediately — those
            // indicate the request itself is bad/blocked, not that the provider is unusable, so
            // retrying against a different provider wouldn't help predictably.
            var lastError: AIError = error
            for fallbackType in fallbackOrder where fallbackType != activeProviderType {
                guard let fallback = providers[fallbackType],
                      await fallback.isAvailable else { continue }
                do {
                    return try await fallback.generate(request)
                } catch let fallbackError as AIError where shouldFallback(for: fallbackError) {
                    lastError = fallbackError
                    continue
                }
            }
            // No fallback succeeded — rethrow the last error encountered.
            throw lastError
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

    /// Send a generation request to a specific provider (regardless of active selection).
    ///
    /// Useful for one-off requests to a different provider without switching the active selection.
    /// Unlike `generate(_:)`, this does not walk `fallbackOrder` on failure.
    public func generate(
        using providerType: ImageProviderType,
        _ request: ImageRequest
    ) async throws -> ImageResult {
        guard let provider = providers[providerType] else {
            throw AIError.notConfigured(
                "No provider configured for \(providerType.displayName)."
            )
        }

        return try await provider.generate(request)
    }
}
