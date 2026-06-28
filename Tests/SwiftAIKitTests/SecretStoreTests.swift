import Foundation
import Testing
@testable import SwiftAIKit

@MainActor
@Suite("SecretStore")
struct SecretStoreTests {

    @Test("set then read returns the value")
    func setThenGet() {
        let store = InMemorySecretStore()
        store.set("sk-ant-123", forKey: "anthropicAPIKey")
        #expect(store.string(forKey: "anthropicAPIKey") == "sk-ant-123")
    }

    @Test("empty string removes the item")
    func emptyRemoves() {
        let store = InMemorySecretStore()
        store.set("value", forKey: "k")
        store.set("", forKey: "k")
        #expect(store.string(forKey: "k") == nil)
    }

    @Test("removeValue clears the item")
    func remove() {
        let store = InMemorySecretStore()
        store.set("value", forKey: "k")
        store.removeValue(forKey: "k")
        #expect(store.string(forKey: "k") == nil)
    }

    @Test("missing key reads as nil")
    func missing() {
        let store = InMemorySecretStore()
        #expect(store.string(forKey: "nope") == nil)
        #expect(store.refreshedString(forKey: "nope") == nil)
    }
}
