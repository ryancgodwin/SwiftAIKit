import Foundation

/// OpenAI-compatible Chat Completions API provider.
///
/// Works with the official OpenAI API, as well as compatible endpoints
/// like Ollama, LM Studio, vLLM, Together AI, Groq, and others.
///
/// Usage:
/// ```swift
/// // Official OpenAI
/// let config = OpenAIProvider.Configuration(apiKey: "sk-...")
/// let provider = OpenAIProvider(configuration: config)
///
/// // Ollama (local, no auth)
/// let config = OpenAIProvider.Configuration(
///     apiKey: "",
///     endpoint: "http://localhost:11434",
///     model: "llama3"
/// )
/// let provider = OpenAIProvider(configuration: config)
/// ```
public actor OpenAIProvider: AIServiceProtocol {

    // MARK: - Configuration

    /// Configuration for the OpenAI-compatible provider.
    public struct Configuration: Sendable {
        public let apiKey: String
        public let endpoint: String
        public let model: String
        public let organizationID: String?

        /// - Parameters:
        ///   - apiKey: The API key. Can be empty for local endpoints (Ollama, LM Studio).
        ///   - endpoint: The base URL. Defaults to OpenAI. Use `http://localhost:11434`
        ///     for Ollama, `http://localhost:1234` for LM Studio, etc.
        ///   - model: The model identifier. Defaults to `gpt-4o`.
        ///   - organizationID: Optional OpenAI organization ID.
        public init(
            apiKey: String,
            endpoint: String = "https://api.openai.com",
            model: String = "gpt-4o",
            organizationID: String? = nil
        ) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.model = model
            self.organizationID = organizationID
        }
    }

    // MARK: - Properties

    public let providerType: AIProviderType = .openAI
    private let configuration: Configuration
    private let session: URLSession

    /// For OpenAI-compatible endpoints, availability means the endpoint is configured.
    /// Local endpoints (Ollama, LM Studio) don't require an API key.
    public var isAvailable: Bool {
        !configuration.endpoint.isEmpty
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
            throw AIError.notConfigured("No OpenAI-compatible endpoint configured.")
        }

        // Build the path — handle endpoints with or without /v1 suffix
        let baseURL = configuration.endpoint.hasSuffix("/")
            ? String(configuration.endpoint.dropLast())
            : configuration.endpoint
        let path = baseURL.hasSuffix("/v1") ? "\(baseURL)/chat/completions" : "\(baseURL)/v1/chat/completions"

        guard let url = URL(string: path) else {
            throw AIError.requestFailed("Invalid endpoint URL: \(configuration.endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "authorization")
        }

        if let orgID = configuration.organizationID, !orgID.isEmpty {
            request.setValue(orgID, forHTTPHeaderField: "openai-organization")
        }

        // Build messages array with system prompt as first message
        var apiMessages: [[String: Any]] = []

        if let systemPrompt {
            apiMessages.append(["role": "system", "content": systemPrompt])
        }

        for message in messages where message.role != .system {
            apiMessages.append([
                "role": message.role.rawValue,
                "content": message.content,
            ])
        }

        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": maxTokens,
            "messages": apiMessages,
        ]

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
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.invalidResponse("Unexpected OpenAI response format.")
        }

        let usage: TokenUsage? = {
            guard let usageDict = json["usage"] as? [String: Any],
                  let input = usageDict["prompt_tokens"] as? Int,
                  let output = usageDict["completion_tokens"] as? Int else {
                return nil
            }
            return TokenUsage(inputTokens: input, outputTokens: output)
        }()

        let finishReason: FinishReason? = {
            guard let reason = firstChoice["finish_reason"] as? String else { return nil }
            return FinishReason(rawValue: reason) ?? .unknown
        }()

        return AIResponse(
            content: content,
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
