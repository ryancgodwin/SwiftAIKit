// Tests/SwiftAIKitUITests/AIProviderSettingsModelTests.swift
import Foundation
import Testing
@testable import SwiftAIKit
@testable import SwiftAIKitUI

@MainActor
@Suite("AIProviderSettingsModel")
struct AIProviderSettingsModelTests {

    private func makeModel() -> (AIProviderSettingsModel, InMemorySecretStore, AIServiceRouter) {
        let router = AIServiceRouter(defaultProvider: .onDevice, defaultsKey: "ui_test_provider")
        let store = InMemorySecretStore()
        let model = AIProviderSettingsModel(router: router, secretStore: store, config: .default)
        return (model, store, router)
    }

    @Test("persistKey writes the key to the secret store")
    func persistKey() {
        let (model, store, _) = makeModel()
        model.apiKey = "sk-ant-new"
        model.persistKey()
        #expect(store.string(forKey: BYOKConfiguration.default.apiKeyAccount) == "sk-ant-new")
    }

    @Test("setting provider updates the router's active provider")
    func providerSwitch() {
        let (model, _, router) = makeModel()
        model.provider = .anthropic
        #expect(router.activeProviderType == .anthropic)
    }

    @Test("loadKeyForReveal pulls the stored key into apiKey and unlocks")
    func reveal() {
        let (model, store, _) = makeModel()
        store.set("sk-ant-stored", forKey: BYOKConfiguration.default.apiKeyAccount)
        model.loadKeyForReveal()
        #expect(model.apiKey == "sk-ant-stored")
        #expect(model.isKeyUnlocked)
    }
}
