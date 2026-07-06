import Foundation

/// A request to generate an image.
public struct ImageRequest: Sendable {
    /// The text prompt describing the desired image.
    public var prompt: String

    /// The desired aspect ratio.
    public var aspect: AspectRatio

    /// The pixel target for the generated image; providers clamp to their supported sizes.
    public var size: ImageSize

    /// A hint describing how the image will be used, for the caller or adapters.
    public var purpose: ImagePurpose

    /// Optional style reference images, for providers that support them.
    public var referenceImages: [Data]

    public init(
        prompt: String,
        aspect: AspectRatio = .wide16x9,
        size: ImageSize = .init(width: 1200, height: 630),
        purpose: ImagePurpose = .hero,
        referenceImages: [Data] = []
    ) {
        self.prompt = prompt
        self.aspect = aspect
        self.size = size
        self.purpose = purpose
        self.referenceImages = referenceImages
    }
}

/// A target aspect ratio for a generated image.
public enum AspectRatio: Sendable, Hashable {
    case square1x1
    case wide16x9
    case portrait9x16
    case custom(w: Int, h: Int)
}

/// A pixel size target for a generated image.
public struct ImageSize: Sendable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A hint describing how a generated image will be used.
public enum ImagePurpose: Sendable, Hashable {
    case hero
    case figure
}
