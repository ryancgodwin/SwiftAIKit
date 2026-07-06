import Foundation

/// Approximate per-image cost lookup, used to fill `ImageResult.costEstimateUSD`.
///
/// **Provider prices move fast — treat every figure here as verify-at-build-time.** This table
/// is a best-effort estimate for display/budgeting purposes, not a billing-accurate source of
/// truth; always check the provider's live billing dashboard for actual charges incurred.
///
/// Sizes are bucketed to the nearest documented tier (see `sizeBucket(for:)`), since providers
/// publish prices for a small number of discrete resolution tiers, not arbitrary pixel
/// dimensions. Unknown `(provider, model)` combinations — including `.svgFallback`, which has no
/// paid tier and hardcodes `0` directly in `SVGFallbackProvider` — return `nil` rather than a
/// guessed figure.
///
/// Figures verified 2026-07-06 against:
/// - Gemini: https://ai.google.dev/gemini-api/docs/pricing (standard tier, per-image, by
///   resolution bucket)
/// - OpenAI: https://developers.openai.com/api/docs/guides/image-generation, under the
///   "Models prior to `gpt-image-2`" legacy pricing table (per-image, by quality tier and size).
///   NOTE: as of the verification date, `https://developers.openai.com/api/docs/pricing` no
///   longer lists `gpt-image-1` at all — it only shows token-based pricing for `gpt-image-2`,
///   `gpt-image-1.5`, and `gpt-image-1-mini`. The images/generate API reference page has no
///   pricing data. The legacy per-image table on the image-generation guide page is the only
///   official source that still documents `gpt-image-1`'s per-image figures.
public enum ImagePricing {

    // MARK: - Public API

    /// Looks up the approximate USD cost for one generated image.
    ///
    /// - Parameters:
    ///   - provider: The provider that generated (or will generate) the image.
    ///   - model: The exact model ID string used for generation. `nil` or unrecognized models
    ///     return `nil`.
    ///   - size: The target pixel size; bucketed to the nearest documented resolution tier.
    /// - Returns: The approximate USD price for one image, or `nil` if the combination isn't in
    ///   the table.
    public static func costEstimateUSD(
        provider: ImageProviderType,
        model: String?,
        size: ImageSize
    ) -> Double? {
        guard let model else { return nil }

        switch provider {
        case .geminiNanoBanana:
            return geminiPriceUSD(model: model, size: size)
        case .openAIImage:
            return openAIPriceUSD(model: model, size: size)
        default:
            return nil
        }
    }

    // MARK: - Gemini

    /// Gemini standard-tier per-image prices, keyed by model ID and resolution bucket.
    ///
    /// Source: https://ai.google.dev/gemini-api/docs/pricing (2026-07-06).
    /// - `gemini-3.1-flash-lite-image` ("Nano Banana 2 Lite"): flat $0.0336 at the 1K bucket
    ///   (no published price ladder across buckets for this model as of the verification date).
    /// - `gemini-3.1-flash-image` ("Nano Banana 2"): $0.067 (1K) / $0.101 (2K) / $0.151 (4K).
    ///   Gemini's pricing page also lists a $0.045 0.5K tier, but it's omitted here — see
    ///   `geminiSizeBucket(for:)` for why that tier is unreachable through this package.
    /// - `gemini-2.5-flash-image` ("Nano Banana"): flat $0.039 up to 1024x1024.
    private static func geminiPriceUSD(model: String, size: ImageSize) -> Double? {
        let bucket = geminiSizeBucket(for: size)
        switch model {
        case "gemini-3.1-flash-lite-image":
            return 0.0336
        case "gemini-3.1-flash-image":
            switch bucket {
            case .oneK: return 0.067
            case .twoK: return 0.101
            case .fourK: return 0.151
            }
        case "gemini-2.5-flash-image":
            return 0.039
        default:
            return nil
        }
    }

    /// Gemini's published resolution buckets, restricted to the ones this package can actually
    /// reach: 1K, 2K, 4K (longest edge, in pixels).
    ///
    /// Gemini's pricing page also documents a 0.5K tier, but `GeminiImageProvider.mapImageSize`
    /// never requests below `"1K"` on the wire — it has no branch that emits anything smaller.
    /// Keeping a `.half` case here would be unreachable dead code with no way to verify it's
    /// even priced correctly, so the bucket floor intentionally follows what the provider
    /// actually requests: any size below the 1K bucket's threshold still prices at the 1K rate.
    private enum GeminiSizeBucket {
        case oneK
        case twoK
        case fourK
    }

    private static func geminiSizeBucket(for size: ImageSize) -> GeminiSizeBucket {
        let longestEdge = max(size.width, size.height)
        switch longestEdge {
        case ..<1536:
            return .oneK
        case 1536..<3072:
            return .twoK
        default:
            return .fourK
        }
    }

    // MARK: - OpenAI

    /// OpenAI per-image prices for `gpt-image-1`, keyed by size string.
    ///
    /// `OpenAIImageProvider` does not send a `quality` parameter, so the API applies its
    /// `"auto"` default. Since the actual quality (and therefore price) `"auto"` resolves to is
    /// not documented and can vary per request, this table prices at the **medium** tier as a
    /// representative estimate — not a guarantee of the exact charge. Verify against the
    /// provider's billing dashboard for exact costs.
    ///
    /// Source: https://developers.openai.com/api/docs/guides/image-generation — the "Models
    /// prior to `gpt-image-2`" legacy pricing table (2026-07-06):
    /// - 1024x1024 (square): low $0.011 / medium $0.042 / high $0.167
    /// - 1024x1536 (portrait): low $0.016 / medium $0.063 / high $0.25
    /// - 1536x1024 (landscape): low $0.016 / medium $0.063 / high $0.25
    ///
    /// `gpt-image-1` itself does NOT appear on OpenAI's deprecations page
    /// (https://developers.openai.com/api/docs/deprecations, checked 2026-07-06) and is not
    /// scheduled for shutdown — only `gpt-image-1-mini`, `gpt-image-1.5`, and
    /// `chatgpt-image-latest` are (2026-12-01), migrating to the token-billed `gpt-image-2`.
    ///
    /// Only `gpt-image-1` is priced here. Newer variants are intentionally left out of this
    /// table (returns `nil`) rather than guessed:
    /// - `gpt-image-1-mini` and `gpt-image-1.5` DO appear with per-image figures on the same
    ///   legacy pricing table as `gpt-image-1` — the reason they're excluded here is NOT that
    ///   they're billed differently, but that both are scheduled for shutdown on 2026-12-01
    ///   (per the deprecations page above), migrating callers to the token-billed `gpt-image-2`.
    ///   Pricing a model this close to shutdown isn't worth maintaining.
    /// - `gpt-image-2` itself is billed per-token rather than a flat per-image figure as of the
    ///   verification date, so it has no per-image number to add here at all.
    /// Add `gpt-image-1-mini`/`gpt-image-1.5` here only if their shutdown is deferred, or add
    /// `gpt-image-2` once a stable per-image estimate can be derived from its token pricing.
    private static func openAIPriceUSD(model: String, size: ImageSize) -> Double? {
        guard model == "gpt-image-1" else { return nil }

        switch openAISizeBucket(for: size) {
        case .square:
            return 0.042
        case .portrait, .landscape:
            return 0.063
        }
    }

    private enum OpenAISizeBucket {
        case square
        case portrait
        case landscape
    }

    private static func openAISizeBucket(for size: ImageSize) -> OpenAISizeBucket {
        if size.width == size.height {
            return .square
        }
        return size.height > size.width ? .portrait : .landscape
    }
}
