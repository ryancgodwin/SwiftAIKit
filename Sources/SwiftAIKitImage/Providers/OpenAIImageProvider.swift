import Foundation
import SwiftAIKit

/// OpenAI image-generation provider (GPT-Image).
///
/// Communicates with the OpenAI Images API `/v1/images/generations` endpoint using raw
/// `URLSession`. No external dependencies.
///
/// Endpoint, request/response shapes, and safety-block signaling verified 2026-07-06 against:
/// - https://developers.openai.com/api/reference/resources/images/methods/generate
///   (request/response field reference for the `images/generations` endpoint)
/// - https://developers.openai.com/api/docs/guides/image-generation (usage guide, curl example)
/// - Community-documented error shapes for `content_policy_violation` / `moderation_blocked`
///   (OpenAI's standard `{"error": {"code", "message", "param", "type"}}` envelope).
///
/// Limitation: unlike Gemini, this endpoint does not accept reference/style images for plain
/// generation — that requires a separate `/v1/images/edits` endpoint, which is out of scope
/// for this provider (YAGNI; not requested by the brief). `ImageRequest.referenceImages` is
/// therefore ignored here.
///
/// Usage:
/// ```swift
/// let config = OpenAIImageProvider.Configuration(apiKey: "sk-...")
/// let provider = OpenAIImageProvider(configuration: config)
/// let result = try await provider.generate(ImageRequest(prompt: "a red panda"))
/// ```
public actor OpenAIImageProvider: ImageServiceProtocol {

    // MARK: - Configuration

    /// Configuration for the OpenAI image provider.
    public struct Configuration: Sendable {
        public let apiKey: String
        public let endpoint: String
        public let model: String
        public let organizationID: String?

        /// Optional lazy key resolver. When set, `generate()` calls this closure at request
        /// time to obtain the API key instead of reading `apiKey` directly. This avoids
        /// triggering a Keychain password prompt at app launch. If the resolver returns `nil`,
        /// `apiKey` is used as fallback.
        ///
        /// The closure must be `@Sendable` because it is stored inside an actor.
        public let apiKeyResolver: (@Sendable () -> String?)?

        /// - Parameters:
        ///   - apiKey: The OpenAI API key.
        ///   - endpoint: The base URL. Defaults to `https://api.openai.com`.
        ///   - model: The model identifier. Defaults to `gpt-image-1`. Verify against
        ///     https://developers.openai.com/api/docs/deprecations before relying on this
        ///     default — provider model IDs move fast (newer variants include
        ///     `gpt-image-1-mini`, `gpt-image-1.5`, `gpt-image-2`). See
        ///     `ImageBYOKConfiguration.openAIDefaultModel` for the current deprecation status.
        ///   - organizationID: Optional OpenAI organization ID.
        ///   - apiKeyResolver: Optional lazy resolver, see above.
        public init(
            apiKey: String,
            endpoint: String = "https://api.openai.com",
            model: String = "gpt-image-1",
            organizationID: String? = nil,
            apiKeyResolver: (@Sendable () -> String?)? = nil
        ) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.model = model
            self.organizationID = organizationID
            self.apiKeyResolver = apiKeyResolver
        }
    }

    // MARK: - Properties

    public let providerType: ImageProviderType = .openAIImage
    private let configuration: Configuration
    private let session: URLSession

    /// Returns `true` when the provider is configured with a way to supply a key — either a
    /// non-empty static `apiKey` or a `apiKeyResolver` closure.
    ///
    /// IMPORTANT: This property intentionally does NOT call `apiKeyResolver`, mirroring
    /// `AnthropicProvider.isAvailable` — see that type's doc comment for the full rationale.
    public var isAvailable: Bool {
        configuration.apiKeyResolver != nil || !configuration.apiKey.isEmpty
    }

    // MARK: - Init

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - ImageServiceProtocol

    public func generate(_ request: ImageRequest) async throws -> ImageResult {
        // Resolve the key lazily at request time — see Configuration.apiKeyResolver.
        let apiKey = configuration.apiKeyResolver?() ?? configuration.apiKey
        guard !apiKey.isEmpty else {
            throw AIError.notConfigured("No OpenAI API key configured.")
        }

        let baseURL = configuration.endpoint.hasSuffix("/")
            ? String(configuration.endpoint.dropLast())
            : configuration.endpoint
        guard let url = URL(string: "\(baseURL)/v1/images/generations") else {
            throw AIError.requestFailed("Invalid endpoint URL: \(configuration.endpoint)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

        if let orgID = configuration.organizationID, !orgID.isEmpty {
            urlRequest.setValue(orgID, forHTTPHeaderField: "openai-organization")
        }

        urlRequest.httpBody = try Self.encodeRequestBody(request, model: configuration.model)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.requestFailed("Invalid response from server.")
        }

        guard httpResponse.statusCode == 200 else {
            if Self.isSafetyBlock(data) {
                let message = Self.parseErrorMessage(data) ?? "Content was blocked by the safety system."
                throw AIError.contentFiltered(message)
            }
            let message = Self.parseErrorMessage(data) ?? "HTTP \(httpResponse.statusCode)"
            throw AIError.requestFailed(message)
        }

        return try Self.parseImagesResponse(
            data,
            model: configuration.model,
            requestedSize: Self.pricingSize(aspect: request.aspect, size: request.size)
        )
    }

    // MARK: - Wire Mapping

    /// Builds the `/v1/images/generations` request body.
    ///
    /// `ImageRequest.referenceImages` is intentionally NOT sent — the generations endpoint
    /// has no field for input images; that requires the separate `/v1/images/edits` endpoint,
    /// which is out of scope here (see the type-level doc comment).
    private static func encodeRequestBody(_ request: ImageRequest, model: String) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "prompt": request.prompt,
            "size": mapSize(aspect: request.aspect, size: request.size),
            "n": 1,
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Maps the request's aspect ratio and pixel size to one of the GPT image models' accepted
    /// `size` strings: `1024x1024`, `1536x1024`, `1024x1536`, or `auto` (per the API reference).
    /// Aspect ratio determines orientation; explicit custom aspects fall back to `auto`.
    static func mapSize(aspect: AspectRatio, size: ImageSize) -> String {
        switch aspect {
        case .square1x1:
            return "1024x1024"
        case .wide16x9:
            return "1536x1024"
        case .portrait9x16:
            return "1024x1536"
        case .custom:
            return "auto"
        }
    }

    /// The actual pixel dimensions requested from OpenAI (mirrors `mapSize(aspect:size:)`), used
    /// only for `ImagePricing` bucketing. `.custom` aspects map to `auto` in the wire request, so
    /// they're priced as the square tier here — a reasonable default absent a documented price
    /// for `auto`.
    ///
    /// - Parameter size: Intentionally unused. OpenAI's `size` wire parameter is derived entirely
    ///   from `aspect` (see `mapSize(aspect:size:)`), so the requested pixel dimensions have no
    ///   bearing on which of the three documented tiers (square/portrait/landscape) applies. The
    ///   parameter is kept (rather than dropped) to mirror `mapSize(aspect:size:)`'s signature and
    ///   to leave room for future finer-grained tiers.
    static func pricingSize(aspect: AspectRatio, size: ImageSize) -> ImageSize {
        switch aspect {
        case .square1x1, .custom:
            return ImageSize(width: 1024, height: 1024)
        case .wide16x9:
            return ImageSize(width: 1536, height: 1024)
        case .portrait9x16:
            return ImageSize(width: 1024, height: 1536)
        }
    }

    // MARK: - Response Parsing

    /// Parses a `/v1/images/generations` 200-OK response body into an `ImageResult`, or throws
    /// `AIError.invalidResponse` if the body doesn't match the expected shape.
    ///
    /// Exposed at `internal` visibility so it can be tested directly against fixture JSON
    /// without a network round-trip (see `OpenAIResponseParsingTests`).
    ///
    /// - Parameter requestedSize: The pixel size requested by the caller, used only for
    ///   `ImagePricing` bucketing (the response body doesn't report output dimensions). Defaults
    ///   to the square 1024x1024 tier, so existing callers/tests that don't pass a size still
    ///   parse.
    static func parseImagesResponse(
        _ data: Data,
        model: String,
        requestedSize: ImageSize = ImageSize(width: 1024, height: 1024)
    ) throws -> ImageResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let firstImage = dataArray.first,
              let base64 = firstImage["b64_json"] as? String,
              let imageData = Data(base64Encoded: base64) else {
            throw AIError.invalidResponse("Unexpected OpenAI images response format.")
        }

        let outputFormat = json["output_format"] as? String ?? "png"
        let mimeType = mimeType(forOutputFormat: outputFormat)

        return ImageResult(
            data: imageData,
            mimeType: mimeType,
            provider: .openAIImage,
            model: model,
            costEstimateUSD: ImagePricing.costEstimateUSD(
                provider: .openAIImage,
                model: model,
                size: requestedSize
            )
        )
    }

    private static func mimeType(forOutputFormat format: String) -> String {
        switch format {
        case "jpeg", "jpg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        default:
            return "image/png"
        }
    }

    /// `error.code` values that indicate the request was rejected by OpenAI's safety/moderation
    /// system, as opposed to an ordinary request error (bad parameter, rate limit, etc.).
    private static let safetyErrorCodes: Set<String> = [
        "moderation_blocked",
        "content_policy_violation",
    ]

    /// Returns `true` if the error envelope's `error.code` identifies a safety/moderation block.
    static func isSafetyBlock(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let code = error["code"] as? String else {
            return false
        }
        return Self.safetyErrorCodes.contains(code)
    }

    /// Extracts a human-readable message from the standard OpenAI error envelope
    /// (`error.code`, `error.message`, `error.param`, `error.type`), or `nil` if the body
    /// doesn't match.
    static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
