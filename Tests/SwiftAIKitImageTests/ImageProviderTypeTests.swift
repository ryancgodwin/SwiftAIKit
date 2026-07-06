import Foundation
import Testing
@testable import SwiftAIKitImage

@Suite("ImageProviderType Tests")
struct ImageProviderTypeTests {

    @Test("ImageProviderType round-trips its raw value")
    func rawValueRoundTrip() {
        let provider = ImageProviderType(rawValue: "geminiNanoBanana")
        #expect(provider.rawValue == "geminiNanoBanana")
        #expect(provider == .geminiNanoBanana)
        #expect(provider.id == "geminiNanoBanana")
    }

    @Test("ImageProviderType has correct display names for known providers")
    func knownDisplayNames() {
        #expect(ImageProviderType.geminiNanoBanana.displayName == "Gemini Nano Banana")
        #expect(ImageProviderType.openAIImage.displayName == "OpenAI GPT-Image")
        #expect(ImageProviderType.svgFallback.displayName == "SVG Fallback")
    }

    @Test("App-defined custom ImageProviderType is usable")
    func customTypeUsable() {
        let custom = ImageProviderType(rawValue: "paperBanana")
        #expect(custom.rawValue == "paperBanana")
        #expect(custom.displayName == "paperBanana")
        #expect(custom != .geminiNanoBanana)
    }

    @Test("ImageProviderType round-trips through Codable")
    func codableRoundTrip() throws {
        let original = ImageProviderType.openAIImage
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageProviderType.self, from: encoded)
        #expect(decoded == original)

        let custom = ImageProviderType(rawValue: "paperBanana")
        let customEncoded = try JSONEncoder().encode(custom)
        let customDecoded = try JSONDecoder().decode(ImageProviderType.self, from: customEncoded)
        #expect(customDecoded == custom)
    }

    @Test("ImageRequest uses documented defaults")
    func imageRequestDefaults() {
        let request = ImageRequest(prompt: "a red panda")
        #expect(request.prompt == "a red panda")
        #expect(request.aspect == .wide16x9)
        #expect(request.size.width == 1200)
        #expect(request.size.height == 630)
        #expect(request.purpose == .hero)
        #expect(request.referenceImages.isEmpty)
    }

    @Test("ImageRequest accepts custom values")
    func imageRequestCustomValues() {
        let refs = [Data([0x01, 0x02])]
        let request = ImageRequest(
            prompt: "a diagram",
            aspect: .square1x1,
            size: ImageSize(width: 512, height: 512),
            purpose: .figure,
            referenceImages: refs
        )
        #expect(request.aspect == .square1x1)
        #expect(request.size.width == 512)
        #expect(request.purpose == .figure)
        #expect(request.referenceImages == refs)
    }

    @Test("AspectRatio supports a custom case")
    func aspectRatioCustomCase() {
        let aspect = AspectRatio.custom(w: 4, h: 3)
        if case let .custom(w, h) = aspect {
            #expect(w == 4)
            #expect(h == 3)
        } else {
            Issue.record("Expected .custom case")
        }
    }

    @Test("ImageResult exposes provider metadata")
    func imageResultFields() {
        let result = ImageResult(
            data: Data([0xFF, 0xD8]),
            mimeType: "image/png",
            provider: .geminiNanoBanana,
            model: "gemini-test-model",
            costEstimateUSD: 0.01
        )
        #expect(result.data == Data([0xFF, 0xD8]))
        #expect(result.mimeType == "image/png")
        #expect(result.provider == .geminiNanoBanana)
        #expect(result.model == "gemini-test-model")
        #expect(result.costEstimateUSD == 0.01)
    }
}
