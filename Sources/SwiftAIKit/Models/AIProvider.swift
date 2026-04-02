import Foundation

/// Identifies an AI provider type.
public enum AIProviderType: String, CaseIterable, Identifiable, Sendable, Codable {
    case onDevice
    case anthropic
    case openAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onDevice: "On-Device (Apple Intelligence)"
        case .anthropic: "Claude (Anthropic)"
        case .openAI: "OpenAI-Compatible"
        }
    }
}
