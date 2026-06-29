#if canImport(FoundationModels)
import FoundationModels

// MARK: - GuidedGenerating

/// A provider capable of Apple FoundationModels guided generation — producing a
/// schema-valid `@Generable` value directly, rather than free-form text the
/// caller must parse. Only the on-device provider supports this.
///
/// Gate any call site with:
/// ```swift
/// if #available(macOS 26.0, iOS 26.0, *),
///    let guided = router.activeGuidedProvider { ... }
/// ```
@available(macOS 26.0, iOS 26.0, *)
public protocol GuidedGenerating: Sendable {

    /// Ask the provider to produce a strongly-typed `@Generable` value.
    ///
    /// - Parameters:
    ///   - prompt: The user-turn prompt (raw text, no role prefix needed).
    ///   - systemPrompt: Optional system-level instructions; pass `nil` to omit.
    ///   - maxTokens: Token budget for the response; `0` or negative lets the
    ///     model use its built-in default.
    ///   - generating: The `@Generable` type to produce.
    /// - Returns: A fully-populated instance of `Content`.
    /// - Throws: `AIError.providerUnavailable` when the model is not ready,
    ///   or `AIError.requestFailed` on generation failure.
    func respondGuided<Content: Generable & Sendable>(
        to prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        generating: Content.Type
    ) async throws -> Content
}
#endif
