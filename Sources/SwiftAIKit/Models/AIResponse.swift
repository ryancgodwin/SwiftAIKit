import Foundation

/// The result of an AI completion request.
public struct AIResponse: Sendable {
    /// The generated text content.
    public let content: String

    /// Token usage for the request, if available from the provider.
    public let usage: TokenUsage?

    /// The model ID that generated this response.
    public let model: String?

    /// The provider-reported finish reason, if available.
    public let finishReason: FinishReason?

    public init(
        content: String,
        usage: TokenUsage? = nil,
        model: String? = nil,
        finishReason: FinishReason? = nil
    ) {
        self.content = content
        self.usage = usage
        self.model = model
        self.finishReason = finishReason
    }
}

/// Token usage statistics for a single request.
public struct TokenUsage: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Why the model stopped generating.
public enum FinishReason: String, Sendable {
    case stop = "stop"
    case maxTokens = "max_tokens"
    case contentFilter = "content_filter"
    case toolUse = "tool_use"
    case unknown
}
