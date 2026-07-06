import Foundation
import SwiftAIKit

/// A dependency-free fallback image provider that asks a text-completion closure to author a
/// self-contained SVG document.
///
/// This provider deliberately does NOT import or reference `AIServiceRouter` or any text-model
/// specifics — it stays decoupled from `SwiftAIKit`'s text stack. Instead, its initializer takes
/// an injected `@Sendable` closure; the consuming app supplies a thin shim over
/// `AIServiceRouter.complete(...).content`. This keeps `SwiftAIKitImage` free of a hard
/// dependency on any particular text provider while still producing model-authored artwork.
///
/// `isAvailable` is always `true` — this provider needs no credentials, so it can always serve
/// as the last resort in a fallback chain.
///
/// ## Behavior
/// 1. Ask the closure for a self-contained `<svg …>` document sized from the request's
///    `ImageSize` (via `viewBox`).
/// 2. Extract the `<svg>...</svg>` slice from the response (models often wrap SVG in markdown
///    code fences or add surrounding prose).
/// 3. Validate well-formedness with `XMLParser` (not `XMLDocument` — this package targets iOS,
///    where `XMLDocument` does not exist).
/// 4. If invalid, retry once: feed the parse failure back to the closure as a repair request.
/// 5. If the repaired response is still invalid (or the closure throws again), fall back to a
///    bundled placeholder SVG template, sized from the request.
///
/// ### Closure-throw behavior (design decision)
/// If the injected closure *throws* (e.g. the underlying text provider is unreachable), this
/// provider treats that the same as a malformed response: it attempts one repair call (feeding
/// back a synthetic "error" message describing the failure), and if that also throws or is
/// still invalid, returns the bundled template rather than propagating the error.
///
/// This provider's entire reason to exist is to be the always-available last resort in a
/// fallback chain (`isAvailable` is unconditionally `true`). If it propagated errors from the
/// text closure, callers relying on it as a guaranteed-success fallback would still see failures,
/// defeating that purpose. The tradeoff: callers lose visibility into *why* the SVG is a generic
/// placeholder instead of model-authored art. That's judged acceptable here since a placeholder
/// image is a strictly better degradation than a thrown error for this provider's use case.
public actor SVGFallbackProvider: ImageServiceProtocol {

    // MARK: - Properties

    public let providerType: ImageProviderType = .svgFallback

    public var isAvailable: Bool { true }

    /// Injected text-completion shim: `(prompt, systemPrompt) async throws -> content`.
    private let complete: @Sendable (_ prompt: String, _ systemPrompt: String?) async throws -> String

    // MARK: - Init

    /// - Parameter complete: A closure the consuming app supplies, typically a thin shim over
    ///   `AIServiceRouter.complete(...).content`. Must be `@Sendable` since it is stored inside
    ///   an actor.
    public init(
        complete: @escaping @Sendable (_ prompt: String, _ systemPrompt: String?) async throws -> String
    ) {
        self.complete = complete
    }

    // MARK: - ImageServiceProtocol

    public func generate(_ request: ImageRequest) async throws -> ImageResult {
        let systemPrompt = Self.systemPrompt

        let firstAttempt = await Self.requestSVG(
            prompt: Self.prompt(for: request),
            systemPrompt: systemPrompt,
            using: complete
        )

        if case .success(let svg) = firstAttempt, Self.isWellFormedXML(svg) {
            return Self.result(svg: svg)
        }

        // Repair retry: feed back the parse error (or the thrown error's description) and ask
        // the closure to try again, exactly once.
        let repairReason = Self.failureReason(for: firstAttempt)
        let repairPrompt = Self.repairPrompt(originalResponse: Self.rawText(for: firstAttempt), reason: repairReason)

        let secondAttempt = await Self.requestSVG(
            prompt: repairPrompt,
            systemPrompt: systemPrompt,
            using: complete
        )

        if case .success(let svg) = secondAttempt, Self.isWellFormedXML(svg) {
            return Self.result(svg: svg)
        }

        return Self.result(svg: Self.template(for: request))
    }

    // MARK: - Closure Invocation

    /// The outcome of one call to the injected `complete` closure.
    private enum AttemptResult {
        case success(String)
        case failure(String, reason: String)
    }

    private static func requestSVG(
        prompt: String,
        systemPrompt: String,
        using complete: @Sendable (_ prompt: String, _ systemPrompt: String?) async throws -> String
    ) async -> AttemptResult {
        do {
            let raw = try await complete(prompt, systemPrompt)
            return .success(extractSVG(from: raw))
        } catch {
            return .failure("", reason: "\(error)")
        }
    }

    private static func failureReason(for attempt: AttemptResult) -> String {
        switch attempt {
        case .success:
            return "the XML was not well-formed"
        case .failure(_, let reason):
            return reason
        }
    }

    private static func rawText(for attempt: AttemptResult) -> String {
        switch attempt {
        case .success(let svg):
            return svg
        case .failure(let raw, _):
            return raw
        }
    }

    // MARK: - Prompting

    private static let systemPrompt = """
    You produce a single self-contained SVG document and nothing else. Respond with only the \
    <svg>...</svg> markup — no markdown code fences, no prose, no explanation.
    """

    private static func prompt(for request: ImageRequest) -> String {
        """
        Create an SVG illustration for: \(request.prompt)

        Requirements:
        - Return a single self-contained <svg> element.
        - Use viewBox="0 0 \(request.size.width) \(request.size.height)".
        - Do not wrap the SVG in markdown code fences or add any surrounding text.
        """
    }

    private static func repairPrompt(originalResponse: String, reason: String) -> String {
        """
        Your previous SVG response was not valid, well-formed XML. Parse failure: \(reason)

        Previous response:
        \(originalResponse)

        Please respond again with a corrected, self-contained, well-formed <svg>...</svg> \
        document only — no markdown code fences, no prose.
        """
    }

    // MARK: - Response Hygiene

    /// Extracts the `<svg …>...</svg>` slice from a raw model response.
    ///
    /// Models frequently wrap SVG in markdown code fences (```svg ... ```) or add prose before
    /// or after the markup. This finds the first `<svg` and the last `</svg>` and returns the
    /// substring between them (inclusive). If either marker is missing, the raw response is
    /// returned unchanged and will simply fail XML validation, triggering the repair/template
    /// path.
    static func extractSVG(from raw: String) -> String {
        guard let openRange = raw.range(of: "<svg"),
              let closeRange = raw.range(of: "</svg>", options: .backwards) else {
            return raw
        }
        guard openRange.lowerBound <= closeRange.lowerBound else {
            return raw
        }
        return String(raw[openRange.lowerBound..<closeRange.upperBound])
    }

    // MARK: - Validation

    /// Validates well-formedness using `XMLParser`. `XMLDocument` is macOS-only; this package
    /// targets iOS 17 + macOS 14, so `XMLParser` (cross-platform) is used instead.
    ///
    /// `XMLParser` is not `Sendable`, so a fresh instance is constructed per call and parsing
    /// stays synchronous within this actor-isolated method — no parser instance crosses an
    /// isolation boundary.
    static func isWellFormedXML(_ string: String) -> Bool {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        return parser.parse()
    }

    // MARK: - Template Fallback

    /// A minimal, always-valid placeholder SVG, sized from the request.
    static func template(for request: ImageRequest) -> String {
        let width = request.size.width
        let height = request.size.height
        return """
        <svg viewBox="0 0 \(width) \(height)" xmlns="http://www.w3.org/2000/svg">
        <rect width="\(width)" height="\(height)" fill="#e5e7eb"/>
        <text x="50%" y="50%" text-anchor="middle" dominant-baseline="middle" \
        font-family="sans-serif" font-size="16" fill="#6b7280">Image unavailable</text>
        </svg>
        """
    }

    // MARK: - Result Construction

    private static func result(svg: String) -> ImageResult {
        ImageResult(
            data: Data(svg.utf8),
            mimeType: "image/svg+xml",
            provider: .svgFallback,
            model: nil,
            costEstimateUSD: 0
        )
    }
}
