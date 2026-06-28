// Tests/SwiftAIKitTests/ProviderReadinessTests.swift
import Foundation
import Testing
@testable import SwiftAIKit

@MainActor
@Suite("ProviderReadiness")
struct ProviderReadinessTests {

    @Test("anthropic with no key reports needsAnthropicKey")
    func anthropicNoKey() {
        let router = AIServiceRouter(defaultProvider: .anthropic, defaultsKey: "test_provider_1")
        router.activeProviderType = .anthropic
        let store = InMemorySecretStore()
        let readiness = ProviderReadinessChecker.check(
            router: router, secretStore: store, config: .default
        )
        #expect(readiness == .needsAnthropicKey)
        #expect(readiness.isReady == false)
        #expect(readiness.userFacingMessage.isEmpty == false)
    }

    @Test("anthropic with a key reports ready")
    func anthropicWithKey() {
        let router = AIServiceRouter(defaultProvider: .anthropic, defaultsKey: "test_provider_2")
        router.activeProviderType = .anthropic
        let store = InMemorySecretStore()
        store.set("sk-ant-xyz", forKey: BYOKConfiguration.default.apiKeyAccount)
        let readiness = ProviderReadinessChecker.check(
            router: router, secretStore: store, config: .default
        )
        #expect(readiness == .ready)
        #expect(readiness.isReady)
    }

    @Test("ready state has an empty user-facing message")
    func readyMessageEmpty() {
        #expect(ProviderReadiness.ready.userFacingMessage.isEmpty)
    }
}
