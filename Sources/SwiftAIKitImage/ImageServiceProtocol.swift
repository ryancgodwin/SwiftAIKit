import Foundation

/// Protocol that all image-generation providers must conform to.
///
/// Each provider (Gemini Nano Banana, OpenAI Image, SVG fallback, etc.) implements this
/// protocol. The consuming app provides the `ImageRequest`; the provider handles transport,
/// authentication, and response parsing.
///
/// Providers are actors for thread safety. All methods are async and throw
/// `AIError` on failure.
public protocol ImageServiceProtocol: Actor {

    /// The provider type this service implements.
    var providerType: ImageProviderType { get }

    /// Whether this provider is currently available and configured.
    ///
    /// Mirrors `AnthropicProvider.isAvailable`: this checks that credentials are configured
    /// (or that no credentials are needed), not that they're valid. It does NOT read the
    /// Keychain — the key is validated at request time.
    var isAvailable: Bool { get }

    /// Send a generation request to the image provider.
    ///
    /// - Parameter request: The image request describing the desired output.
    /// - Returns: The generated image result.
    /// - Throws: `AIError` on failure.
    func generate(_ request: ImageRequest) async throws -> ImageResult
}
