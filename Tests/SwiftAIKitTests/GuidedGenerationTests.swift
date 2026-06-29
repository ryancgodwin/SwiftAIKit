import Foundation
import Testing
@testable import SwiftAIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@Generable
struct ProbeContact: Sendable {
    @Guide(description: "the person's full name") var name: String
    @Guide(description: "the person's email address") var email: String
}
#endif

@Suite("Guided generation")
struct GuidedGenerationTests {

    @Test("OnDeviceProvider conforms to GuidedGenerating and extracts a typed value live (or skips)")
    func guidedLiveOrSkip() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, *) else { print("SKIP: needs macOS 26+"); return }
        guard case .available = SystemLanguageModel.default.availability else {
            print("SKIP: Apple Intelligence unavailable: \(SystemLanguageModel.default.availability)"); return
        }
        let provider = OnDeviceProvider()
        let contact: ProbeContact = try await provider.respondGuided(
            to: "Extract the contact: Jane Doe, jane@example.com",
            systemPrompt: "Extract structured contact info.",
            maxTokens: 200,
            generating: ProbeContact.self
        )
        #expect(!contact.name.trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(contact.email.localizedCaseInsensitiveContains("jane@example.com"))
        print("GUIDED live: name=\(contact.name) email=\(contact.email)")
        #else
        print("SKIP: FoundationModels not importable")
        #endif
    }

    @Test("router exposes activeGuidedProvider when on-device is active")
    @MainActor
    func routerExposesGuided() {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        let router = AIServiceRouter(defaultProvider: .onDevice, defaultsKey: "cp_guided_test")
        router.configure(.onDevice, with: OnDeviceProvider())
        router.activeProviderType = .onDevice
        #expect(router.activeGuidedProvider != nil)
        #endif
    }
}
