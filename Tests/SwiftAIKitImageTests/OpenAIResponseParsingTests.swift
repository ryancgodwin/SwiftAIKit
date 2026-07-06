import Foundation
import Testing
@testable import SwiftAIKitImage
import SwiftAIKit

/// Parsing tests for `OpenAIImageProvider` against captured sample JSON (success, error, and
/// safety-block shapes) as documented at
/// https://developers.openai.com/api/reference/resources/images/methods/generate and
/// https://developers.openai.com/api/docs/guides/image-generation.
///
/// These tests are offline and deterministic: they exercise `OpenAIImageProvider`'s internal
/// response-parsing function directly against fixture JSON, with no network calls. Unlike
/// Gemini, OpenAI's images endpoint signals both plain errors and safety/moderation blocks as
/// non-200 HTTP responses using the same `{"error": {...}}` envelope — there is no in-band
/// "blocked but 200 OK" shape for this endpoint.
@Suite("OpenAIImageProvider Response Parsing")
struct OpenAIResponseParsingTests {

    // MARK: Fixtures

    /// A successful `images/generations` response for a GPT image model: `data[0].b64_json`
    /// carries the base64 PNG bytes. GPT image models always return b64_json (no `url` field),
    /// per the API reference.
    static let successJSON = """
    {
      "created": 1713833628,
      "background": "opaque",
      "data": [ { "b64_json": "aGVsbG8gd29ybGQ=" } ],
      "output_format": "png",
      "quality": "high",
      "size": "1024x1024",
      "usage": {
        "input_tokens": 50,
        "input_tokens_details": { "image_tokens": 0, "text_tokens": 50 },
        "output_tokens": 1290,
        "output_tokens_details": { "image_tokens": 1290, "text_tokens": 0 },
        "total_tokens": 1340
      }
    }
    """

    /// A plain non-200 error body using OpenAI's standard error envelope
    /// (`error.code`, `error.message`, `error.param`, `error.type`).
    static let errorJSON = """
    {
      "error": {
        "code": "invalid_size",
        "message": "The requested size is not supported for model 'gpt-image-1'.",
        "param": "size",
        "type": "invalid_request_error"
      }
    }
    """

    /// A moderation/safety-block error body. Also HTTP non-200, using the same envelope, but
    /// with `error.code` set to a moderation-specific value (`moderation_blocked` or
    /// `content_policy_violation`) — this is how safety blocks are distinguished from other
    /// request errors for this endpoint.
    static let moderationBlockedJSON = """
    {
      "error": {
        "code": "moderation_blocked",
        "message": "Your request was rejected by the safety system.",
        "param": null,
        "type": "image_generation_user_error"
      }
    }
    """

    static let contentPolicyViolationJSON = """
    {
      "error": {
        "code": "content_policy_violation",
        "message": "Your request was rejected as a result of our safety system.",
        "param": null,
        "type": "invalid_request_error"
      }
    }
    """

    /// Malformed body: valid JSON, but missing the expected `data[0].b64_json` structure.
    static let malformedJSON = """
    { "created": 1713833628, "data": [ { } ] }
    """

    // MARK: - Success

    @Test("parses data[0].b64_json image bytes from a successful response")
    func parsesSuccessResponse() throws {
        let result = try OpenAIImageProvider.parseImagesResponse(
            Data(Self.successJSON.utf8),
            model: "gpt-image-1"
        )

        #expect(result.mimeType == "image/png")
        #expect(result.data == Data(base64Encoded: "aGVsbG8gd29ybGQ=")!)
        #expect(result.provider == .openAIImage)
        #expect(result.model == "gpt-image-1")
        // Default requestedSize (1024x1024, square) prices at the medium-quality tier.
        #expect(result.costEstimateUSD == 0.042)
    }

    // MARK: - Error mapping (status-code driven)

    @Test("maps a plain error envelope to a message usable by requestFailed")
    func parsesErrorEnvelope() {
        let message = OpenAIImageProvider.parseErrorMessage(Data(Self.errorJSON.utf8))
        #expect(message == "The requested size is not supported for model 'gpt-image-1'.")
    }

    @Test("identifies moderation_blocked as a safety block")
    func identifiesModerationBlocked() {
        #expect(OpenAIImageProvider.isSafetyBlock(Data(Self.moderationBlockedJSON.utf8)) == true)
    }

    @Test("identifies content_policy_violation as a safety block")
    func identifiesContentPolicyViolation() {
        #expect(OpenAIImageProvider.isSafetyBlock(Data(Self.contentPolicyViolationJSON.utf8)) == true)
    }

    @Test("does not classify a plain invalid_request_error as a safety block")
    func plainErrorIsNotSafetyBlock() {
        #expect(OpenAIImageProvider.isSafetyBlock(Data(Self.errorJSON.utf8)) == false)
    }

    // MARK: - Malformed body

    @Test("throws invalidResponse for a malformed body missing b64_json")
    func throwsInvalidResponseForMalformedBody() {
        do {
            _ = try OpenAIImageProvider.parseImagesResponse(Data(Self.malformedJSON.utf8), model: "gpt-image-1")
            Issue.record("Expected invalidResponse to be thrown")
        } catch AIError.invalidResponse {
            // expected
        } catch {
            Issue.record("Expected AIError.invalidResponse, got \(error)")
        }
    }

    @Test("throws invalidResponse for non-JSON garbage bytes")
    func throwsInvalidResponseForGarbageBytes() {
        let garbage = Data([0xFF, 0x00, 0xDE, 0xAD])
        #expect(throws: AIError.self) {
            try OpenAIImageProvider.parseImagesResponse(garbage, model: "gpt-image-1")
        }
    }

    // MARK: - Aspect / size mapping

    @Test("maps AspectRatio cases to the documented gpt-image size strings")
    func mapsSize() {
        let square = OpenAIImageProvider.mapSize(aspect: .square1x1, size: ImageSize(width: 1024, height: 1024))
        #expect(square == "1024x1024")

        let wide = OpenAIImageProvider.mapSize(aspect: .wide16x9, size: ImageSize(width: 1536, height: 1024))
        #expect(wide == "1536x1024")

        let portrait = OpenAIImageProvider.mapSize(aspect: .portrait9x16, size: ImageSize(width: 1024, height: 1536))
        #expect(portrait == "1024x1536")

        let custom = OpenAIImageProvider.mapSize(aspect: .custom(w: 4, h: 3), size: ImageSize(width: 800, height: 600))
        #expect(custom == "auto")
    }

    // MARK: - Lazy key resolver (mirrors AnthropicProvider / LazyAnthropicKeyTests)

    @Test("isAvailable returns true when apiKeyResolver is set, without invoking it")
    func isAvailableWithResolverDoesNotInvokeIt() async {
        let resolverCalled = AtomicFlagForOpenAIImageTests()
        let config = OpenAIImageProvider.Configuration(
            apiKey: "",
            apiKeyResolver: {
                resolverCalled.set()
                return "resolved-key"
            }
        )
        let provider = OpenAIImageProvider(configuration: config)

        let available = await provider.isAvailable

        #expect(available == true)
        #expect(resolverCalled.value == false, "isAvailable must not invoke the resolver")
    }

    @Test("isAvailable returns true for a static apiKey with no resolver")
    func isAvailableWithStaticKey() async {
        let config = OpenAIImageProvider.Configuration(apiKey: "sk-static-key")
        let provider = OpenAIImageProvider(configuration: config)
        #expect(await provider.isAvailable == true)
    }

    @Test("isAvailable returns false when neither resolver nor static key is set")
    func isAvailableFalseWhenNeitherSet() async {
        let config = OpenAIImageProvider.Configuration(apiKey: "")
        let provider = OpenAIImageProvider(configuration: config)
        #expect(await provider.isAvailable == false)
    }
}

/// Thread-safe boolean flag settable from a `@Sendable` closure, for lazy-resolver tests.
private final class AtomicFlagForOpenAIImageTests: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}
