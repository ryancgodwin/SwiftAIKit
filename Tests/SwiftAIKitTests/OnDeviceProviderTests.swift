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
