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

    // MARK: - Prompt building (pure, testable on any OS)

    /// A single user turn is sent verbatim (the common case); multi-message
    /// histories are role-labeled. Kept pure so it is unit-testable without
    /// the on-device model.
    static func buildPrompt(from messages: [AIMessage]) -> String {
        if messages.count == 1, messages[0].role == .user {
            return messages[0].content
        }
        return messages.map { msg in
            switch msg.role {
            case .system:    return "System: \(msg.content)"
            case .user:      return "User: \(msg.content)"
            case .assistant: return "Assistant: \(msg.content)"
            }
        }.joined(separator: "\n")
    }

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
                systemPrompt: systemPrompt,
                maxTokens: maxTokens
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

    /// Builds on-device generation options. `maxTokens <= 0` means "no explicit
    /// cap" (the model's own default limit applies); a positive value is passed
    /// through as `maximumResponseTokens`.
    @available(macOS 26.0, iOS 26.0, *)
    static func generationOptions(maxTokens: Int) -> GenerationOptions {
        GenerationOptions(maximumResponseTokens: maxTokens > 0 ? maxTokens : nil)
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func completeWithFoundationModels(
        messages: [AIMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AIResponse {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw AIError.providerUnavailable(availabilityReason(model.availability))
        }

        let session = LanguageModelSession(instructions: systemPrompt ?? "")
        let prompt = Self.buildPrompt(from: messages)

        do {
            let response = try await session.respond(to: prompt, options: Self.generationOptions(maxTokens: maxTokens))
            let content = response.content
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIError.requestFailed("On-device model returned an empty response.")
            }
            return AIResponse(
                content: content,
                usage: nil,
                model: "apple-intelligence-on-device",
                finishReason: .stop
            )
        } catch let error as AIError {
            throw error
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

// MARK: - GuidedGenerating Conformance

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
extension OnDeviceProvider: GuidedGenerating {

    public func respondGuided<Content: Generable & Sendable>(
        to prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        generating: Content.Type
    ) async throws -> Content {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw AIError.providerUnavailable(availabilityReason(model.availability))
        }
        let session = LanguageModelSession(instructions: systemPrompt ?? "")
        do {
            let response = try await session.respond(
                to: prompt,
                generating: Content.self,
                options: Self.generationOptions(maxTokens: maxTokens)
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw AIError.requestFailed("On-device guided generation failed: \(error.localizedDescription)")
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.requestFailed(error.localizedDescription)
        }
    }
}
#endif
