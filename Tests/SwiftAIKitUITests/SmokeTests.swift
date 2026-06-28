import Testing
import SwiftAIKit
@testable import SwiftAIKitUI

@Suite("SwiftAIKitUI smoke")
struct SwiftAIKitUISmokeTests {
    @Test("SwiftAIKit dependency is linked and reachable from SwiftAIKitUI")
    func dependencyLinked() {
        // Proves the new target compiles AND links its SwiftAIKit dependency.
        #expect(AIProviderType.allCases.count == 3)
    }
}
