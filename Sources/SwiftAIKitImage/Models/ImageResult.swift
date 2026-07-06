import Foundation

/// The result of an image-generation request.
public struct ImageResult: Sendable {
    /// The image bytes: PNG data, or UTF-8 encoded SVG for the fallback provider.
    public let data: Data

    /// The MIME type of `data`, e.g. `"image/png"` or `"image/svg+xml"`.
    public let mimeType: String

    /// The provider that generated this image.
    public let provider: ImageProviderType

    /// The model ID that generated this image, if available.
    public let model: String?

    /// An estimated cost in USD for this request, if known.
    public let costEstimateUSD: Double?

    public init(
        data: Data,
        mimeType: String,
        provider: ImageProviderType,
        model: String? = nil,
        costEstimateUSD: Double? = nil
    ) {
        self.data = data
        self.mimeType = mimeType
        self.provider = provider
        self.model = model
        self.costEstimateUSD = costEstimateUSD
    }
}
