import Foundation
import SwiftAIKit

/// Gemini image-generation provider ("Nano Banana").
///
/// Communicates with the Gemini API `generateContent` endpoint using raw `URLSession`.
/// No external dependencies.
///
/// Endpoint, request/response shapes, and safety-block signaling verified 2026-07-06 against:
/// - https://ai.google.dev/api/generate-content (REST reference: `Blob`, `Part`, `Candidate`,
///   `PromptFeedback`, `GenerationConfig`, `ImageConfig` schemas)
/// - https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta (live Discovery
///   document — authoritative source for exact JSON field names and enum values)
/// - https://ai.google.dev/gemini-api/docs/image-generation and
///   https://ai.google.dev/gemini-api/docs/models (current Nano Banana model IDs)
///
/// Usage:
/// ```swift
/// let config = GeminiImageProvider.Configuration(apiKey: "AIza...")
/// let provider = GeminiImageProvider(configuration: config)
/// let result = try await provider.generate(ImageRequest(prompt: "a red panda"))
/// ```
public actor GeminiImageProvider: ImageServiceProtocol {

    // MARK: - Configuration

    /// Configuration for the Gemini image provider.
    public struct Configuration: Sendable {
        public let apiKey: String
        public let endpoint: String
        public let model: String

        /// Optional lazy key resolver. When set, `generate()` calls this closure at request
        /// time to obtain the API key instead of reading `apiKey` directly. This avoids
        /// triggering a Keychain password prompt at app launch — the prompt fires only when
        /// the user actually makes a request. If the resolver returns `nil`, `apiKey` is used
        /// as fallback.
        ///
        /// The closure must be `@Sendable` because it is stored inside an actor.
        public let apiKeyResolver: (@Sendable () -> String?)?

        /// - Parameters:
        ///   - apiKey: The Gemini API key.
        ///   - endpoint: The base URL. Defaults to the Gemini API base.
        ///   - model: The model identifier. Defaults to `gemini-3.1-flash-lite-image`
        ///     ("Nano Banana 2 Lite"), the fastest and cheapest current general-purpose image
        ///     model. Verify against https://ai.google.dev/gemini-api/docs/models before
        ///     relying on this default — provider model IDs move fast.
        ///   - apiKeyResolver: Optional lazy resolver, see above.
        public init(
            apiKey: String,
            endpoint: String = "https://generativelanguage.googleapis.com",
            model: String = "gemini-3.1-flash-lite-image",
            apiKeyResolver: (@Sendable () -> String?)? = nil
        ) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.model = model
            self.apiKeyResolver = apiKeyResolver
        }
    }

    // MARK: - Properties

    public let providerType: ImageProviderType = .geminiNanoBanana
    private let configuration: Configuration
    private let session: URLSession

    /// Returns `true` when the provider is configured with a way to supply a key — either a
    /// non-empty static `apiKey` or a `apiKeyResolver` closure.
    ///
    /// IMPORTANT: This property intentionally does NOT call `apiKeyResolver`. Invoking the
    /// resolver here would read the Keychain on every availability check, defeating the
    /// purpose of lazy loading. Actual key presence is validated at request time inside
    /// `generate()`.
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
        // Resolve the key lazily at request time. The resolver captures a Sendable
        // SecretStore and reads it only now — not at configure time.
        let apiKey = configuration.apiKeyResolver?() ?? configuration.apiKey
        guard !apiKey.isEmpty else {
            throw AIError.notConfigured("No Gemini API key configured.")
        }

        let urlString = "\(configuration.endpoint)/v1beta/models/\(configuration.model):generateContent"
        guard let url = URL(string: urlString) else {
            throw AIError.requestFailed("Invalid endpoint URL: \(urlString)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try Self.encodeRequestBody(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.requestFailed("Invalid response from server.")
        }

        guard httpResponse.statusCode == 200 else {
            let message = Self.parseErrorMessage(data) ?? "HTTP \(httpResponse.statusCode)"
            throw AIError.requestFailed(message)
        }

        return try Self.parseGenerateContentResponse(data, model: configuration.model, requestedSize: request.size)
    }

    // MARK: - Wire Mapping

    /// Builds the `generateContent` request body.
    ///
    /// Reference images are included as additional `inlineData` parts (the Gemini image
    /// models accept inline image input for editing/style-reference use cases, up to several
    /// images per request per current docs). Aspect ratio and size are mapped into
    /// `generationConfig.imageConfig`, whose supported `aspectRatio`/`imageSize` string values
    /// are enumerated in the `ImageConfig` schema of the live Discovery document.
    private static func encodeRequestBody(_ request: ImageRequest) throws -> Data {
        var parts: [[String: Any]] = [["text": request.prompt]]

        for imageData in request.referenceImages {
            parts.append([
                "inlineData": [
                    "mimeType": "image/png",
                    "data": imageData.base64EncodedString(),
                ],
            ])
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": parts] as [String: Any],
            ],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"],
                "imageConfig": [
                    "aspectRatio": mapAspectRatio(request.aspect),
                    "imageSize": mapImageSize(request.size),
                ],
            ] as [String: Any],
        ]

        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Maps `AspectRatio` to one of the Gemini `ImageConfig.aspectRatio` supported values:
    /// `1:1`, `1:4`, `4:1`, `1:8`, `8:1`, `2:3`, `3:2`, `3:4`, `4:3`, `4:5`, `5:4`, `9:16`,
    /// `16:9`, `21:9` (per the live Discovery document's `ImageConfig` schema).
    static func mapAspectRatio(_ aspect: AspectRatio) -> String {
        switch aspect {
        case .square1x1:
            return "1:1"
        case .wide16x9:
            return "16:9"
        case .portrait9x16:
            return "9:16"
        case .custom(let w, let h):
            guard w > 0, h > 0 else { return "1:1" }
            let divisor = gcd(w, h)
            return "\(w / divisor):\(h / divisor)"
        }
    }

    /// Maps the request's pixel size target to the nearest supported `ImageConfig.imageSize`
    /// bucket: `1K`, `2K`, or `4K` (per the live Discovery document; `512` is also accepted
    /// but omitted here since `ImageRequest.size` defaults well above that range).
    static func mapImageSize(_ size: ImageSize) -> String {
        let longestEdge = max(size.width, size.height)
        switch longestEdge {
        case ..<1536:
            return "1K"
        case 1536..<3072:
            return "2K"
        default:
            return "4K"
        }
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(a, 1)
    }

    // MARK: - Response Parsing

    /// Parses a `generateContent` 200-OK response body into an `ImageResult`, or throws
    /// `AIError.contentFiltered` if the response indicates a safety block, or
    /// `AIError.invalidResponse` if the body doesn't match the expected shape.
    ///
    /// Exposed at `internal` visibility so it can be tested directly against fixture JSON
    /// without a network round-trip (see `GeminiResponseParsingTests`).
    ///
    /// - Parameter requestedSize: The pixel size requested by the caller, used only for
    ///   `ImagePricing` bucketing (the response body doesn't report actual output dimensions,
    ///   and Gemini's `imageConfig.imageSize` already constrained generation to the bucket
    ///   derived from this same value — see `mapImageSize(_:)`). Defaults to a value bucketing
    ///   to Gemini's 1K tier, so existing callers/tests that don't pass a size still parse.
    static func parseGenerateContentResponse(
        _ data: Data,
        model: String,
        requestedSize: ImageSize = ImageSize(width: 1024, height: 1024)
    ) throws -> ImageResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse("Gemini response was not valid JSON.")
        }

        // A blocked prompt has no candidates at all; `promptFeedback.blockReason` explains why.
        if let promptFeedback = json["promptFeedback"] as? [String: Any],
           let blockReason = promptFeedback["blockReason"] as? String {
            throw AIError.contentFiltered("Gemini blocked the prompt: \(blockReason)")
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first else {
            throw AIError.invalidResponse("Unexpected Gemini response format: no candidates.")
        }

        // A candidate can be present but still blocked, signaled via `finishReason` (e.g.
        // IMAGE_SAFETY, IMAGE_PROHIBITED_CONTENT, IMAGE_OTHER, IMAGE_RECITATION, NO_IMAGE,
        // SAFETY, PROHIBITED_CONTENT, BLOCKLIST — see `Candidate.finishReason` enum).
        if let finishReason = firstCandidate["finishReason"] as? String,
           Self.safetyFinishReasons.contains(finishReason) {
            throw AIError.contentFiltered("Gemini blocked the response: \(finishReason)")
        }

        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIError.invalidResponse("Unexpected Gemini response format: no content parts.")
        }

        for part in parts {
            if let inlineData = part["inlineData"] as? [String: Any],
               let base64 = inlineData["data"] as? String,
               let imageData = Data(base64Encoded: base64) {
                let mimeType = inlineData["mimeType"] as? String ?? "image/png"
                return ImageResult(
                    data: imageData,
                    mimeType: mimeType,
                    provider: .geminiNanoBanana,
                    model: model,
                    costEstimateUSD: ImagePricing.costEstimateUSD(
                        provider: .geminiNanoBanana,
                        model: model,
                        size: requestedSize
                    )
                )
            }
        }

        throw AIError.invalidResponse("Gemini response contained no inlineData image part.")
    }

    /// `Candidate.finishReason` values that indicate the image was withheld for safety reasons,
    /// per the live Discovery document's `Candidate` schema enum.
    private static let safetyFinishReasons: Set<String> = [
        "SAFETY",
        "PROHIBITED_CONTENT",
        "BLOCKLIST",
        "SPII",
        "IMAGE_SAFETY",
        "IMAGE_PROHIBITED_CONTENT",
        "IMAGE_OTHER",
        "IMAGE_RECITATION",
        "NO_IMAGE",
    ]

    /// Extracts a human-readable message from the standard Gemini error envelope
    /// (`error.code`, `error.message`, `error.status`), or `nil` if the body doesn't match.
    static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
