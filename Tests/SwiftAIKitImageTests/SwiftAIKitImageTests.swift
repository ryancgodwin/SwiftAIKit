import Testing
@testable import SwiftAIKitImage

@Suite("SwiftAIKitImage Tests")
struct SwiftAIKitImageTests {

    @Test("Module imports successfully")
    func moduleImports() {
        let _ = SwiftAIKitImage()
    }
}
