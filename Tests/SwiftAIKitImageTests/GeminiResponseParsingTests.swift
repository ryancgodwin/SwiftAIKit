import Foundation
import Testing
@testable import SwiftAIKitImage
import SwiftAIKit

/// Parsing tests for `GeminiImageProvider` against captured sample JSON (success, error,
/// and safety-block shapes) as documented by the Gemini API `generateContent` reference
/// (https://ai.google.dev/api/generate-content) and the live Discovery document at
/// https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta.
///
/// These tests are offline and deterministic: they exercise `GeminiImageProvider`'s internal
/// response-parsing function directly against fixture JSON, with no network calls.
@Suite("GeminiImageProvider Response Parsing")
struct GeminiResponseParsingTests {

    // MARK: Fixtures

    /// A successful `generateContent` response: one candidate whose `content.parts` contains
    /// a text part followed by an `inlineData` part carrying the base64 PNG bytes.
    /// Field names (`inlineData`, `mimeType`, `data`) verified against the `Blob` and `Part`
    /// schemas in the live Discovery document.
    static let successJSON = """
    {
      "candidates": [
        {
          "content": {
            "parts": [
              { "text": "Here is a nano banana dish in a fancy restaurant." },
              { "inlineData": { "mimeType": "image/png", "data": "aGVsbG8gd29ybGQ=" } }
            ],
            "role": "model"
          },
          "finishReason": "STOP",
          "index": 0
        }
      ],
      "usageMetadata": { "promptTokenCount": 12, "candidatesTokenCount": 1290, "totalTokenCount": 1302 },
      "modelVersion": "gemini-3.1-flash-image"
    }
    """

    /// A non-200 error body, matching the standard Gemini API error envelope
    /// (`error.code`, `error.message`, `error.status`).
    static let errorJSON = """
    {
      "error": {
        "code": 400,
        "message": "Invalid value at 'generation_config.image_config.aspect_ratio' (TYPE_STRING), \\"16x9\\"",
        "status": "INVALID_ARGUMENT"
      }
    }
    """

    /// A 200 response whose prompt was blocked before any candidates were generated.
    /// `promptFeedback.blockReason` values verified against the `PromptFeedback` schema:
    /// one of BLOCK_REASON_UNSPECIFIED, SAFETY, OTHER, BLOCKLIST, PROHIBITED_CONTENT, IMAGE_SAFETY.
    static let promptBlockedJSON = """
    {
      "promptFeedback": {
        "blockReason": "PROHIBITED_CONTENT",
        "safetyRatings": [ { "category": "HARM_CATEGORY_DANGEROUS_CONTENT", "probability": "HIGH" } ]
      }
    }
    """

    /// A 200 response with a candidate present but flagged: `finishReason` is one of the
    /// image-safety values from the `Candidate.finishReason` enum (IMAGE_SAFETY,
    /// IMAGE_PROHIBITED_CONTENT, IMAGE_OTHER, IMAGE_RECITATION, NO_IMAGE), with no inlineData part.
    static let candidateSafetyBlockedJSON = """
    {
      "candidates": [
        {
          "content": { "parts": [], "role": "model" },
          "finishReason": "IMAGE_SAFETY",
          "index": 0
        }
      ],
      "modelVersion": "gemini-3.1-flash-image"
    }
    """

    /// Malformed body: valid JSON, but missing the expected candidate/part structure.
    static let malformedJSON = """
    { "unexpected": "shape" }
    """

    // MARK: - Success

    @Test("parses inlineData image bytes and mimeType from a successful response")
    func parsesSuccessResponse() throws {
        let result = try GeminiImageProvider.parseGenerateContentResponse(
            Data(Self.successJSON.utf8),
            model: "gemini-3.1-flash-image"
        )

        #expect(result.mimeType == "image/png")
        #expect(result.data == Data(base64Encoded: "aGVsbG8gd29ybGQ=")!)
        #expect(result.provider == .geminiNanoBanana)
        #expect(result.model == "gemini-3.1-flash-image")
        #expect(result.costEstimateUSD == nil)
    }

    // MARK: - Error envelope

    @Test("maps the standard error envelope to a message usable by requestFailed")
    func parsesErrorEnvelope() {
        let message = GeminiImageProvider.parseErrorMessage(Data(Self.errorJSON.utf8))
        #expect(message == "Invalid value at 'generation_config.image_config.aspect_ratio' (TYPE_STRING), \"16x9\"")
    }

    // MARK: - Safety blocks

    @Test("throws contentFiltered when promptFeedback.blockReason is present")
    func throwsContentFilteredForPromptBlock() {
        #expect(throws: AIError.self) {
            try GeminiImageProvider.parseGenerateContentResponse(
                Data(Self.promptBlockedJSON.utf8),
                model: "gemini-3.1-flash-image"
            )
        }

        do {
            _ = try GeminiImageProvider.parseGenerateContentResponse(
                Data(Self.promptBlockedJSON.utf8),
                model: "gemini-3.1-flash-image"
            )
            Issue.record("Expected contentFiltered to be thrown")
        } catch let AIError.contentFiltered(reason) {
            #expect(reason.contains("PROHIBITED_CONTENT"))
        } catch {
            Issue.record("Expected AIError.contentFiltered, got \(error)")
        }
    }

    @Test("throws contentFiltered when a candidate's finishReason signals an image safety block")
    func throwsContentFilteredForCandidateSafetyBlock() {
        do {
            _ = try GeminiImageProvider.parseGenerateContentResponse(
                Data(Self.candidateSafetyBlockedJSON.utf8),
                model: "gemini-3.1-flash-image"
            )
            Issue.record("Expected contentFiltered to be thrown")
        } catch let AIError.contentFiltered(reason) {
            #expect(reason.contains("IMAGE_SAFETY"))
        } catch {
            Issue.record("Expected AIError.contentFiltered, got \(error)")
        }
    }

    // MARK: - Malformed body

    @Test("throws invalidResponse for a malformed body missing inlineData")
    func throwsInvalidResponseForMalformedBody() {
        #expect(throws: AIError.self) {
            try GeminiImageProvider.parseGenerateContentResponse(
                Data(Self.malformedJSON.utf8),
                model: "gemini-3.1-flash-image"
            )
        }

        do {
            _ = try GeminiImageProvider.parseGenerateContentResponse(
                Data(Self.malformedJSON.utf8),
                model: "gemini-3.1-flash-image"
            )
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
            try GeminiImageProvider.parseGenerateContentResponse(garbage, model: "gemini-3.1-flash-image")
        }
    }

    // MARK: - Aspect / size mapping

    @Test("maps AspectRatio cases to the documented ImageConfig.aspectRatio strings")
    func mapsAspectRatio() {
        #expect(GeminiImageProvider.mapAspectRatio(.square1x1) == "1:1")
        #expect(GeminiImageProvider.mapAspectRatio(.wide16x9) == "16:9")
        #expect(GeminiImageProvider.mapAspectRatio(.portrait9x16) == "9:16")
        #expect(GeminiImageProvider.mapAspectRatio(.custom(w: 4, h: 3)) == "4:3")
    }

    @Test("maps ImageSize to the documented ImageConfig.imageSize buckets")
    func mapsImageSize() {
        #expect(GeminiImageProvider.mapImageSize(ImageSize(width: 1024, height: 1024)) == "1K")
        #expect(GeminiImageProvider.mapImageSize(ImageSize(width: 2048, height: 1024)) == "2K")
        #expect(GeminiImageProvider.mapImageSize(ImageSize(width: 4096, height: 4096)) == "4K")
    }

    // MARK: - Lazy key resolver (mirrors AnthropicProvider / LazyAnthropicKeyTests)

    @Test("isAvailable returns true when apiKeyResolver is set, without invoking it")
    func isAvailableWithResolverDoesNotInvokeIt() async {
        let resolverCalled = AtomicFlagForGeminiTests()
        let config = GeminiImageProvider.Configuration(
            apiKey: "",
            apiKeyResolver: {
                resolverCalled.set()
                return "resolved-key"
            }
        )
        let provider = GeminiImageProvider(configuration: config)

        let available = await provider.isAvailable

        #expect(available == true)
        #expect(resolverCalled.value == false, "isAvailable must not invoke the resolver")
    }

    @Test("isAvailable returns true for a static apiKey with no resolver")
    func isAvailableWithStaticKey() async {
        let config = GeminiImageProvider.Configuration(apiKey: "AIza-static-key")
        let provider = GeminiImageProvider(configuration: config)
        #expect(await provider.isAvailable == true)
    }

    @Test("isAvailable returns false when neither resolver nor static key is set")
    func isAvailableFalseWhenNeitherSet() async {
        let config = GeminiImageProvider.Configuration(apiKey: "")
        let provider = GeminiImageProvider(configuration: config)
        #expect(await provider.isAvailable == false)
    }
}

/// Thread-safe boolean flag settable from a `@Sendable` closure, for lazy-resolver tests.
private final class AtomicFlagForGeminiTests: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}
