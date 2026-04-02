import Foundation
import Testing
@testable import SwiftAIKit

@Suite("SwiftAIKit Core Tests")
struct SwiftAIKitTests {

    @Test("AIMessage initializes with correct properties")
    func messageInit() {
        let msg = AIMessage(role: .user, content: "Hello")
        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
    }

    @Test("AIProviderType has correct display names")
    func providerDisplayNames() {
        #expect(AIProviderType.onDevice.displayName == "On-Device (Apple Intelligence)")
        #expect(AIProviderType.anthropic.displayName == "Claude (Anthropic)")
        #expect(AIProviderType.openAI.displayName == "OpenAI-Compatible")
    }

    @Test("AIProviderType is CaseIterable with all three cases")
    func providerCases() {
        #expect(AIProviderType.allCases.count == 3)
    }

    @Test("AIResponse content is accessible")
    func responseContent() {
        let response = AIResponse(
            content: "Test response",
            usage: TokenUsage(inputTokens: 10, outputTokens: 20),
            model: "test-model",
            finishReason: .stop
        )
        #expect(response.content == "Test response")
        #expect(response.usage?.totalTokens == 30)
        #expect(response.model == "test-model")
        #expect(response.finishReason == .stop)
    }

    @Test("AIError provides localized descriptions")
    func errorDescriptions() {
        let error = AIError.notConfigured("Missing key")
        #expect(error.errorDescription?.contains("Missing key") == true)
    }

    @Test("AnthropicProvider reports unavailable without API key")
    func anthropicUnavailableWithoutKey() async {
        let provider = AnthropicProvider(configuration: .init(apiKey: ""))
        let available = await provider.isAvailable
        #expect(available == false)
    }

    @Test("AnthropicProvider reports available with API key")
    func anthropicAvailableWithKey() async {
        let provider = AnthropicProvider(configuration: .init(apiKey: "sk-test"))
        let available = await provider.isAvailable
        #expect(available == true)
    }

    @Test("OpenAIProvider reports available with endpoint configured")
    func openAIAvailable() async {
        let provider = OpenAIProvider(
            configuration: .init(apiKey: "", endpoint: "http://localhost:11434", model: "llama3")
        )
        let available = await provider.isAvailable
        #expect(available == true)
    }

    @Test("OnDeviceProvider initializes without crash")
    func onDeviceInit() {
        let _ = OnDeviceProvider()
    }

    @Test("AIServiceRouter defaults to specified provider", .tags(.router))
    @MainActor
    func routerDefaultProvider() {
        let router = AIServiceRouter(
            defaultProvider: .anthropic,
            defaultsKey: "test_router_provider_\(UUID().uuidString)"
        )
        #expect(router.activeProviderType == .anthropic)
    }

    @Test("AIServiceRouter throws when no provider configured", .tags(.router))
    @MainActor
    func routerThrowsWithoutProvider() async {
        let router = AIServiceRouter(
            defaultProvider: .anthropic,
            defaultsKey: "test_router_empty_\(UUID().uuidString)"
        )
        do {
            _ = try await router.complete(
                messages: [AIMessage(role: .user, content: "Hi")],
                maxTokens: 10
            )
            Issue.record("Expected AIError.notConfigured")
        } catch {
            #expect(error is AIError)
        }
    }

    @Test("AIServiceRouter tracks registered providers", .tags(.router))
    @MainActor
    func routerRegisteredProviders() {
        let router = AIServiceRouter(
            defaultProvider: .onDevice,
            defaultsKey: "test_router_reg_\(UUID().uuidString)"
        )
        router.configure(.onDevice, with: OnDeviceProvider())
        router.configure(.anthropic, with: AnthropicProvider(configuration: .init(apiKey: "test")))

        #expect(router.registeredProviders.count == 2)
    }
}

extension Tag {
    @Tag static var router: Self
}
