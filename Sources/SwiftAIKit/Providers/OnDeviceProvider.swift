import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device AI provider using Apple Intelligence (FoundationModels framework).
///
/// Requires macOS 26+ or iOS 26+ and Apple Silicon with Apple Intelligence enabled.
/// Falls back gracefully with `AIError.providerUnavailable` on unsupported hardware.
///
/// Unlike API-based providers, this provider processes everything locally — no data
/// leaves the device. The trade-off is smaller model capacity and limited output length.
///
/// Usage:
/// ```swift
/// let provider = OnDeviceProvider()
/// let response = try await provider.complete(
///     messages: [AIMessage(role: .user, content: "Explain gravity")],
///     systemPrompt: "You are a physics tutor.",
///     maxTokens: 2048
/// )
/// ```
public actor OnDeviceProvider: AIServiceProtocol {

    // MARK: - Properties

    public let providerType: AIProviderType = .onDevice

    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return checkAvailability()
        }
        #endif
        return false
    }

    // MARK: - Init

    public init() {}

    // MARK: - AIServiceProtocol

    public func complete(
        messages: [AIMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AIResponse {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return try await completeWithFoundationModels(
                messages: messages,
                systemPrompt: systemPrompt
            )
        }
        #endif
        throw AIError.providerUnavailable(
            "On-device AI requires macOS 26+ or iOS 26+ with Apple Intelligence enabled."
        )
    }

    // MARK: - FoundationModels Implementation

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private func checkAvailability() -> Bool {
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            return true
        }
        return false
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func completeWithFoundationModels(
        messages: [AIMessage],
        systemPrompt: String?
    ) async throws -> AIResponse {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw AIError.providerUnavailable(availabilityReason(model.availability))
        }

        let instructions = systemPrompt ?? ""
        let session = LanguageModelSession(instructions: instructions)

        // Build a single prompt from the conversation messages.
        // FoundationModels uses a session-based API, so we concatenate the
        // conversation into a single input for the respond() call.
        let conversationText = messages.map { msg in
            switch msg.role {
            case .system:
                return "System: \(msg.content)"
            case .user:
                return "User: \(msg.content)"
            case .assistant:
                return "Assistant: \(msg.content)"
            }
        }.joined(separator: "\n")

        do {
            let response = try await session.respond(to: conversationText)
            return AIResponse(
                content: response.content,
                usage: nil,
                model: "apple-intelligence-on-device",
                finishReason: .stop
            )
        } catch {
            throw AIError.requestFailed(error.localizedDescription)
        }
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func availabilityReason(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled. Enable it in System Settings."
        case .unavailable(.modelNotReady):
            return "The model is still downloading. Please wait and try again."
        default:
            return "The on-device model is not available."
        }
    }
    #endif
}
