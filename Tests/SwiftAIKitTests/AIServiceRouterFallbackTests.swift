import Foundation
import Testing
@testable import SwiftAIKit

/// Configurable stub text provider: fixed availability, canned reply or thrown error,
/// and a call counter so tests can assert which chain members were actually tried.
private actor StubTextProvider: AIServiceProtocol {
    let providerType: AIProviderType
    private let available: Bool
    private let error: AIError?
    private let reply: String
    private(set) var completeCallCount = 0

    init(providerType: AIProviderType, isAvailable: Bool, error: AIError? = nil, reply: String = "ok") {
        self.providerType = providerType
        self.available = isAvailable
        self.error = error
        self.reply = reply
    }

    var isAvailable: Bool { available }

    func complete(messages: [AIMessage], systemPrompt: String?, maxTokens: Int) async throws -> AIResponse {
        completeCallCount += 1
        if let error { throw error }
        return AIResponse(content: reply)
    }
}

@MainActor
@Suite("AIServiceRouter fallback chain")
struct AIServiceRouterFallbackTests {

    private func uniqueDefaultsKey(_ name: String = #function) -> String {
        "aikit_fallback_tests_\(name)"
    }

    private func ask(_ router: AIServiceRouter) async throws -> AIResponse {
        try await router.complete(messages: [AIMessage(role: .user, content: "hi")],
                                  systemPrompt: nil, maxTokens: 64)
    }

    @Test("""
    complete() continues past a fallback candidate that is registered, available, but throws \
    a fallback-eligible error, and returns the result from the next candidate in the chain
    """)
    func fallbackChainSkipsThrowingCandidateAndReachesTerminal() async throws {
        let router = AIServiceRouter(defaultProvider: .onDevice, defaultsKey: uniqueDefaultsKey())
        let active = StubTextProvider(providerType: .onDevice, isAvailable: true,
                                      error: .providerUnavailable("model not loaded"))
        // Registered and passes the isAvailable pre-check, but complete() throws notConfigured
        // (the real-world shape: a provider whose cheap availability check can't see a bad key).
        let throwingFallback = StubTextProvider(providerType: .anthropic, isAvailable: true,
                                                error: .notConfigured("no API key"))
        let terminal = StubTextProvider(providerType: .openAI, isAvailable: true, reply: "from terminal")

        router.configure(.onDevice, with: active)
        router.configure(.anthropic, with: throwingFallback)
        router.configure(.openAI, with: terminal)
        router.fallbackOrder = [.onDevice, .anthropic, .openAI]

        let response = try await ask(router)

        #expect(response.content == "from terminal")
        #expect(await throwingFallback.completeCallCount == 1)   // it WAS tried…
        #expect(await terminal.completeCallCount == 1)           // …and the chain continued past it
    }

    @Test("""
    complete() propagates a non-fallback-eligible error thrown by a middle fallback candidate \
    immediately, without trying later candidates in the chain
    """)
    func fallbackChainPropagatesNonEligibleErrorImmediately() async throws {
        let router = AIServiceRouter(defaultProvider: .onDevice, defaultsKey: uniqueDefaultsKey())
        // Active throws an ELIGIBLE error so the fallback walk actually starts.
        let active = StubTextProvider(providerType: .onDevice, isAvailable: true,
                                      error: .providerUnavailable("model not loaded"))
        let throwingFallback = StubTextProvider(providerType: .anthropic, isAvailable: true,
                                                error: .requestFailed("HTTP 500"))
        let terminal = StubTextProvider(providerType: .openAI, isAvailable: true)

        router.configure(.onDevice, with: active)
        router.configure(.anthropic, with: throwingFallback)
        router.configure(.openAI, with: terminal)
        router.fallbackOrder = [.onDevice, .anthropic, .openAI]

        do {
            _ = try await ask(router)
            Issue.record("expected requestFailed to propagate")
        } catch let error as AIError {
            guard case .requestFailed = error else {
                Issue.record("expected requestFailed, got \(error)")
                return
            }
        }
        #expect(await terminal.completeCallCount == 0)   // never reached — bad request, not a bad provider
    }

    @Test("complete() rethrows the LAST eligible error when the whole chain is exhausted")
    func rethrowsLastErrorWhenChainExhausted() async throws {
        let router = AIServiceRouter(defaultProvider: .onDevice, defaultsKey: uniqueDefaultsKey())
        let active = StubTextProvider(providerType: .onDevice, isAvailable: true,
                                      error: .providerUnavailable("model not loaded"))
        let lastFallback = StubTextProvider(providerType: .anthropic, isAvailable: true,
                                            error: .notConfigured("no API key"))

        router.configure(.onDevice, with: active)
        router.configure(.anthropic, with: lastFallback)
        router.fallbackOrder = [.onDevice, .anthropic]

        do {
            _ = try await ask(router)
            Issue.record("expected the exhausted chain to throw")
        } catch let error as AIError {
            guard case .notConfigured = error else {
                Issue.record("expected the LAST candidate's error (notConfigured), got \(error)")
                return
            }
        }
    }
}
