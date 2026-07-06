import Foundation
import Testing
@testable import SwiftAIKitImage
import SwiftAIKit

/// Drives a stubbed text-completion closure through a scripted sequence of responses,
/// recording how many times it was called and what prompt/systemPrompt it last saw.
///
/// Each element of `responses` is either a string to return or an error to throw. If more
/// calls happen than there are scripted responses, the last response repeats.
actor StubCompletion {
    enum Response {
        case text(String)
        case failure(Error)
    }

    private var responses: [Response]
    private(set) var callCount = 0
    private(set) var prompts: [String] = []
    private(set) var systemPrompts: [String?] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func callAsFunction(_ prompt: String, _ systemPrompt: String?) async throws -> String {
        callCount += 1
        prompts.append(prompt)
        systemPrompts.append(systemPrompt)
        let index = min(callCount - 1, responses.count - 1)
        switch responses[index] {
        case .text(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

@Suite("SVGFallbackProvider Tests")
struct SVGFallbackProviderTests {

    private let wellFormedSVG = "<svg viewBox=\"0 0 100 100\" xmlns=\"http://www.w3.org/2000/svg\">" +
        "<circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>"

    @Test("providerType is svgFallback")
    func providerTypeIsSVGFallback() async {
        let stub = StubCompletion([.text("")])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)
        #expect(await provider.providerType == .svgFallback)
    }

    @Test("isAvailable is always true")
    func isAvailableAlwaysTrue() async {
        let stub = StubCompletion([.text("")])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)
        #expect(await provider.isAvailable == true)
    }

    @Test("well-formed SVG from the closure passes through unchanged")
    func wellFormedSVGPassesThrough() async throws {
        let stub = StubCompletion([.text(wellFormedSVG)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        let returnedSVG = String(data: result.data, encoding: .utf8)
        #expect(returnedSVG == wellFormedSVG)
        #expect(await stub.callCount == 1)
    }

    @Test("extracts SVG from markdown code fences and surrounding prose")
    func extractsSVGFromMarkdownFence() async throws {
        let wrapped = "Sure, here's your image:\n\n```svg\n\(wellFormedSVG)\n```\n\nLet me know if you'd like changes."
        let stub = StubCompletion([.text(wrapped)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        let returnedSVG = String(data: result.data, encoding: .utf8)
        #expect(returnedSVG == wellFormedSVG)
    }

    @Test("malformed first response triggers exactly one repair call, repaired response is used")
    func malformedResponseTriggersOneRepair() async throws {
        let malformed = "<svg viewBox=\"0 0 100 100\"><circle cx=\"50\" cy=\"50\" r=\"40\"></svg>" // mismatched tag
        let stub = StubCompletion([.text(malformed), .text(wellFormedSVG)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        let returnedSVG = String(data: result.data, encoding: .utf8)
        #expect(returnedSVG == wellFormedSVG)
        #expect(await stub.callCount == 2)
    }

    @Test("repair call receives the parse error fed back to the closure")
    func repairCallReceivesParseError() async throws {
        let malformed = "<svg viewBox=\"0 0 100 100\"><circle cx=\"50\" cy=\"50\" r=\"40\"></svg>"
        let stub = StubCompletion([.text(malformed), .text(wellFormedSVG)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        _ = try await provider.generate(ImageRequest(prompt: "a red circle"))

        let secondPrompt = await stub.prompts[1]
        #expect(secondPrompt.contains(malformed))
        #expect(await stub.callCount == 2)
    }

    @Test("second failure returns the bundled template, closure called exactly twice")
    func secondFailureReturnsTemplate() async throws {
        let malformed1 = "<svg><unclosed></svg>"
        let malformed2 = "still not valid xml <svg"
        let stub = StubCompletion([.text(malformed1), .text(malformed2)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        #expect(await stub.callCount == 2)
        let returnedSVG = try #require(String(data: result.data, encoding: .utf8), "expected valid UTF-8")
        #expect(returnedSVG.contains("<svg"))
        #expect(returnedSVG != malformed1)
        #expect(returnedSVG != malformed2)
        #expect(SVGFallbackProvider.isValidSVG(returnedSVG))
    }

    @Test("costEstimateUSD is 0 and mimeType is image/svg+xml")
    func costAndMimeType() async throws {
        let stub = StubCompletion([.text(wellFormedSVG)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        #expect(result.costEstimateUSD == 0)
        #expect(result.mimeType == "image/svg+xml")
        #expect(result.provider == .svgFallback)
    }

    @Test("template result is sized from the request's ImageSize")
    func templateIsSizedFromRequest() async throws {
        let stub = StubCompletion([
            .failure(AIError.requestFailed("boom")),
            .failure(AIError.requestFailed("boom again")),
        ])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let request = ImageRequest(prompt: "a red circle", size: ImageSize(width: 400, height: 200))
        let result = try await provider.generate(request)

        let svg = try #require(String(data: result.data, encoding: .utf8), "expected valid UTF-8")
        #expect(svg.contains("400"))
        #expect(svg.contains("200"))
    }

    @Test("closure throwing on first call triggers one repair call, then returns the template on second throw")
    func closureThrowingReturnsTemplate() async throws {
        let stub = StubCompletion([
            .failure(AIError.requestFailed("network down")),
            .failure(AIError.requestFailed("still down")),
        ])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        #expect(await stub.callCount == 2)
        let svg = try #require(String(data: result.data, encoding: .utf8), "expected valid UTF-8")
        #expect(SVGFallbackProvider.isValidSVG(svg))
        #expect(result.mimeType == "image/svg+xml")
        #expect(result.costEstimateUSD == 0)
    }

    @Test("closure succeeding after a first throw uses the repaired response")
    func closureThrowsOnceThenSucceeds() async throws {
        let stub = StubCompletion([
            .failure(AIError.requestFailed("transient")),
            .text(wellFormedSVG),
        ])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        #expect(await stub.callCount == 2)
        let returnedSVG = String(data: result.data, encoding: .utf8)
        #expect(returnedSVG == wellFormedSVG)
    }

    @Test("well-formed non-SVG XML on both attempts returns the bundled template, closure called exactly twice")
    func wellFormedNonSVGReturnsTemplate() async throws {
        let nonSVG = "<html><body>hello</body></html>"
        let stub = StubCompletion([.text(nonSVG), .text(nonSVG)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        #expect(await stub.callCount == 2)
        let returnedSVG = try #require(String(data: result.data, encoding: .utf8), "expected valid UTF-8")
        #expect(returnedSVG != nonSVG)
        #expect(returnedSVG.contains("<svg"))
        #expect(SVGFallbackProvider.isValidSVG(returnedSVG))
    }

    @Test("well-formed non-SVG XML on first attempt, valid SVG on repair, returns the repaired SVG")
    func wellFormedNonSVGThenValidSVGReturnsRepairedSVG() async throws {
        let nonSVG = "<html><body>hello</body></html>"
        let stub = StubCompletion([.text(nonSVG), .text(wellFormedSVG)])
        let provider = SVGFallbackProvider(complete: stub.callAsFunction)

        let result = try await provider.generate(ImageRequest(prompt: "a red circle"))

        #expect(await stub.callCount == 2)
        let returnedSVG = String(data: result.data, encoding: .utf8)
        #expect(returnedSVG == wellFormedSVG)
    }
}
