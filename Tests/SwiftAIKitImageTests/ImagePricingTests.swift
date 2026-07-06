import Foundation
import Testing
@testable import SwiftAIKitImage

@Suite("ImagePricing")
struct ImagePricingTests {

    // MARK: - Known combinations

    @Test("gemini flash-lite-image 1K standard price is known")
    func geminiFlashLiteImage1K() {
        let price = ImagePricing.costEstimateUSD(
            provider: .geminiNanoBanana,
            model: "gemini-3.1-flash-lite-image",
            size: ImageSize(width: 1024, height: 1024)
        )
        #expect(price == 0.0336)
    }

    @Test("gemini flash-image (non-lite) 1K standard price is known")
    func geminiFlashImage1K() {
        let price = ImagePricing.costEstimateUSD(
            provider: .geminiNanoBanana,
            model: "gemini-3.1-flash-image",
            size: ImageSize(width: 1024, height: 1024)
        )
        #expect(price == 0.067)
    }

    @Test("gemini flash-image 4K standard price is known")
    func geminiFlashImage4K() {
        let price = ImagePricing.costEstimateUSD(
            provider: .geminiNanoBanana,
            model: "gemini-3.1-flash-image",
            size: ImageSize(width: 4096, height: 4096)
        )
        #expect(price == 0.151)
    }

    @Test("gemini flash-image sub-1K size (below the provider's smallest requestable bucket) prices at the 1K tier")
    func geminiFlashImageSmallSizeFallsIntoOneKBucket() {
        // GeminiImageProvider.mapImageSize never requests below "1K" on the wire, so the
        // pricing bucket floor follows what the provider actually requests — there is no
        // reachable 0.5K tier.
        let price = ImagePricing.costEstimateUSD(
            provider: .geminiNanoBanana,
            model: "gemini-3.1-flash-image",
            size: ImageSize(width: 512, height: 512)
        )
        #expect(price == 0.067)
    }

    @Test("gpt-image-1 1024x1024 medium-quality price is known")
    func gptImage1Square() {
        let price = ImagePricing.costEstimateUSD(
            provider: .openAIImage,
            model: "gpt-image-1",
            size: ImageSize(width: 1024, height: 1024)
        )
        #expect(price == 0.042)
    }

    @Test("gpt-image-1 1536x1024 (landscape) medium-quality price is known")
    func gptImage1Landscape() {
        let price = ImagePricing.costEstimateUSD(
            provider: .openAIImage,
            model: "gpt-image-1",
            size: ImageSize(width: 1536, height: 1024)
        )
        #expect(price == 0.063)
    }

    @Test("gpt-image-1 1024x1536 (portrait) medium-quality price is known")
    func gptImage1Portrait() {
        let price = ImagePricing.costEstimateUSD(
            provider: .openAIImage,
            model: "gpt-image-1",
            size: ImageSize(width: 1024, height: 1536)
        )
        #expect(price == 0.063)
    }

    // MARK: - Unknown combinations -> nil

    @Test("unknown model returns nil")
    func unknownModel() {
        let price = ImagePricing.costEstimateUSD(
            provider: .geminiNanoBanana,
            model: "some-future-model-nobody-has-heard-of",
            size: ImageSize(width: 1024, height: 1024)
        )
        #expect(price == nil)
    }

    @Test("unknown provider type returns nil")
    func unknownProvider() {
        let price = ImagePricing.costEstimateUSD(
            provider: ImageProviderType(rawValue: "someCustomProvider"),
            model: "gpt-image-1",
            size: ImageSize(width: 1024, height: 1024)
        )
        #expect(price == nil)
    }

    @Test("svgFallback provider returns nil from the pricing table (providers hardcode 0 directly)")
    func svgFallbackNotInTable() {
        let price = ImagePricing.costEstimateUSD(
            provider: .svgFallback,
            model: nil,
            size: ImageSize(width: 1024, height: 1024)
        )
        #expect(price == nil)
    }

    @Test("nil model returns nil")
    func nilModel() {
        let price = ImagePricing.costEstimateUSD(
            provider: .geminiNanoBanana,
            model: nil,
            size: ImageSize(width: 1024, height: 1024)
        )
        #expect(price == nil)
    }

    // MARK: - Size bucketing

    @Test("gemini flash-image odd size buckets to nearest known size (1536 -> 2K)")
    func geminiFlashImageBucketing() {
        let price = ImagePricing.costEstimateUSD(
            provider: .geminiNanoBanana,
            model: "gemini-3.1-flash-image",
            size: ImageSize(width: 2048, height: 2048)
        )
        #expect(price == 0.101)
    }
}
