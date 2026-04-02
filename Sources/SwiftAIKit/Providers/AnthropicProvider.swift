import Foundation

/// Anthropic Messages API provider.
///
/// Communicates with the Anthropic API (or any compatible endpoint) using
/// raw `URLSession`. No external dependencies.
///
/// Usage:
/// ```swift
/// let config = AnthropicProvider.Configuration(apiKey: "sk-ant-...")
/// let provider = AnthropicProvider(configuration: config)
/// let response = try await provider.complete(
///     messages: [AIMessage(role: .user, content: "Hello")],
///     systemPrompt: "You are a helpful assistant.",
///     maxTokens: 1024
/// )
/// ```
public actor AnthropicProvider: AIServiceProtocol {

    // MARK: - Configuration

    /// Configuration for the Anthropic provider.
    public struct Configuration: Sendable {
        public let apiKey: String
        public let endpoint: String
        public let model: String
        public let apiVersion: String

        public init(
            apiKey: String,
            endpoint: String = "https://api.anthropic.com",
            model: String = "claude-sonnet-4-20250514",
            apiVersion: String = "2023-06-01"
        ) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.model = model
            self.apiVersion = apiVersion
        }
    }

    // MARK: - Properties

    public let providerType: AIProviderType = .anthropic
    private let configuration: Configuration
    private let session: URLSession

    public var isAvailable: Bool {
        !configuration.apiKey.isEmpty
    }

    // MARK: - Init

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - AIServiceProtocol

    public func complete(
        messages: [AIMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AIResponse {
        guard isAvailable else {
            throw AIError.notConfigured("No Anthropic API key configured.")
        }

        let url = URL(string: "\(configuration.endpoint)/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(configuration.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": maxTokens,
            "messages": messages.filter { $0.role != .system }.map { message in
                ["role": message.role.rawValue, "content": message.content] as [String: Any]
            },
        ]

        if let systemPrompt {
            body["system"] = systemPrompt
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.requestFailed("Invalid response from server.")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseAPIError(from: data)
                ?? "HTTP \(httpResponse.statusCode)"
            throw AIError.requestFailed(errorMessage)
        }

        return try parseResponse(data)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> AIResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIError.invalidResponse("Unexpected Anthropic response format.")
        }

        let usage: TokenUsage? = {
            guard let usageDict = json["usage"] as? [String: Any],
                  let input = usageDict["input_tokens"] as? Int,
                  let output = usageDict["output_tokens"] as? Int else {
                return nil
            }
            return TokenUsage(inputTokens: input, outputTokens: output)
        }()

        let finishReason: FinishReason? = {
            guard let reason = json["stop_reason"] as? String else { return nil }
            return FinishReason(rawValue: reason) ?? .unknown
        }()

        return AIResponse(
            content: text,
            usage: usage,
            model: json["model"] as? String,
            finishReason: finishReason
        )
    }

    private func parseAPIError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
