import Testing
@testable import SwiftAIKit

@Suite("OnDeviceProvider prompt building")
struct OnDeviceProviderPromptTests {

    @Test("single user message → bare content, no role prefix")
    func singleUser() {
        let prompt = OnDeviceProvider.buildPrompt(from: [AIMessage(role: .user, content: "Summarize this.")])
        #expect(prompt == "Summarize this.")
    }

    @Test("multi-message → role-labeled join")
    func multi() {
        let prompt = OnDeviceProvider.buildPrompt(from: [
            AIMessage(role: .user, content: "Hi"),
            AIMessage(role: .assistant, content: "Hello"),
            AIMessage(role: .user, content: "Bye"),
        ])
        #expect(prompt == "User: Hi\nAssistant: Hello\nUser: Bye")
    }

    @Test("empty messages → empty string")
    func empty() {
        #expect(OnDeviceProvider.buildPrompt(from: []) == "")
    }
}

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite("OnDeviceProvider live model (guarded)")
struct OnDeviceProviderLiveTests {

    @Test("complete() returns non-empty content when Apple Intelligence is available")
    func liveCompleteIfAvailable() async throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, *) else {
            print("SKIP: FoundationModels requires macOS/iOS 26+.")
            return
        }
        guard case .available = SystemLanguageModel.default.availability else {
            print("SKIP: Apple Intelligence not available in this test process: \(SystemLanguageModel.default.availability)")
            return
        }
        let provider = OnDeviceProvider()
        let response = try await provider.complete(
            messages: [AIMessage(role: .user, content: "Reply with exactly one word: pong")],
            systemPrompt: "You are a terse assistant. Answer in one word.",
            maxTokens: 32
        )
        #expect(!response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(response.model == "apple-intelligence-on-device")
        print("LIVE on-device response: \(response.content)")
        #else
        print("SKIP: FoundationModels not importable on this platform.")
        #endif
    }
}
