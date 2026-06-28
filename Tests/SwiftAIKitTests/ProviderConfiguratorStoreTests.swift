import Foundation
import Testing
@testable import SwiftAIKit

@MainActor
@Suite("ProviderConfigurator + SecretStore")
struct ProviderConfiguratorStoreTests {

    @Test("configures anthropic provider from the secret store")
    func configuresFromStore() async {
        let router = AIServiceRouter(defaultProvider: .anthropic, defaultsKey: "test_cfg_1")
        let store = InMemorySecretStore()
        store.set("sk-ant-stored", forKey: BYOKConfiguration.default.apiKeyAccount)

        ProviderConfigurator.configureAnthropic(
            router: router, secretStore: store, config: .default
        )
        router.activeProviderType = .anthropic
        // A configured provider with a non-empty key reports available.
        let available = await router.isProviderAvailable(.anthropic)
        #expect(available)
    }
}
