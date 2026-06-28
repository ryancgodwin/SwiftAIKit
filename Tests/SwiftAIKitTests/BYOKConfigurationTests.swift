import Testing
@testable import SwiftAIKit

@Suite("BYOKConfiguration")
struct BYOKConfigurationTests {

    @Test("default config has anthropic.com endpoint and a sonnet model")
    func defaults() {
        let c = BYOKConfiguration.default
        #expect(c.defaultEndpoint == "https://api.anthropic.com")
        #expect(c.defaultModel.contains("claude"))
        #expect(c.apiKeyAccount == "anthropicAPIKey")
        #expect(c.providerDefaultsKey == "aiProvider")
    }
}
