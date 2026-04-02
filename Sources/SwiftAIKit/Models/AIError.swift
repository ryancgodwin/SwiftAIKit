import Foundation

/// Errors that can occur during AI service operations.
public enum AIError: LocalizedError, Sendable {
    /// The provider is not available (e.g., on-device model not supported on this hardware).
    case providerUnavailable(String)

    /// No API key or credentials configured for the provider.
    case notConfigured(String)

    /// The API request failed (network error, invalid response, rate limit, etc.).
    case requestFailed(String)

    /// The response could not be parsed into the expected format.
    case invalidResponse(String)

    /// The provider reported a content filtering or safety issue.
    case contentFiltered(String)

    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let reason):
            "Provider unavailable: \(reason)"
        case .notConfigured(let reason):
            "Not configured: \(reason)"
        case .requestFailed(let reason):
            "Request failed: \(reason)"
        case .invalidResponse(let reason):
            "Invalid response: \(reason)"
        case .contentFiltered(let reason):
            "Content filtered: \(reason)"
        }
    }
}
