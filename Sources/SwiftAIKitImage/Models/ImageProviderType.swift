import Foundation

/// Identifies an image-generation provider type.
///
/// Unlike `AIProviderType`, this is an extensible `RawRepresentable` struct rather than a
/// closed `enum` — apps may define their own provider types (e.g. `ImageProviderType(rawValue:
/// "paperBanana")`) without needing changes in this package.
public struct ImageProviderType: RawRepresentable, Hashable, Sendable, Codable, Identifiable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var id: String { rawValue }

    public static let geminiNanoBanana = ImageProviderType(rawValue: "geminiNanoBanana")
    public static let openAIImage = ImageProviderType(rawValue: "openAIImage")
    public static let svgFallback = ImageProviderType(rawValue: "svgFallback")

    /// A human-readable name for known provider types, falling back to the raw value.
    public var displayName: String {
        switch self {
        case .geminiNanoBanana: "Gemini Nano Banana"
        case .openAIImage: "OpenAI GPT-Image"
        case .svgFallback: "SVG Fallback"
        default: rawValue
        }
    }
}
