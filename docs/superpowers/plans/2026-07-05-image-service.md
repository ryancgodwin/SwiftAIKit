# SwiftAIKit Image Service — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a text-to-image capability to SwiftAIKit that mirrors the existing text-provider
architecture (`AIServiceProtocol` / `AIServiceRouter` / concrete provider actors), so consuming
apps can generate images through a unified, provider-agnostic interface with automatic
fallback — starting with Google **Nano Banana** (Gemini image models) and **OpenAI GPT-Image**,
plus a dependency-free **SVG fallback**. First consumer: the Between Fields Studio app.

**Architecture:** Add a **new library target `SwiftAIKitImage`** that depends on the core
`SwiftAIKit` target (to reuse `SecretStore`, `AIError`, and the lazy-key-resolver pattern) but
stays Foundation-only and SwiftUI-free. It introduces an `ImageServiceProtocol` (actor), an
`@MainActor @Observable ImageServiceRouter`, provider actors, and a `SecretStore`-backed
configurator. The provider *type* is a `RawRepresentable` struct (not a closed enum) so
apps can register their own providers — e.g. Between Fields Studio's app-level **PaperBanana**
adapter — without modifying the package.

**Tech Stack:** Swift 6.0 (strict concurrency), SwiftPM, Foundation + raw `URLSession`, Swift
Testing (`import Testing`). No SwiftUI, no external dependencies.

## Global Constraints

- **Swift 6.0** strict concurrency (`.swiftLanguageMode(.v6)`), copied from existing targets.
- **Zero external dependencies** — Apple frameworks + raw `URLSession` only.
- **`SwiftAIKitImage` must not import SwiftUI** — it is a logic/transport target like core
  `SwiftAIKit`. Any image *preview UI* lives in the consuming app, not here.
- Reuse core types: `SecretStore`, `InMemorySecretStore`, `AIError`. Do **not** duplicate them.
- **4-space indentation**, 120-char soft line limit, `public` for API surface, `private` for
  internals, `// MARK: -` section headers, trailing commas in multi-line collections.
- **Never log or transmit secret values** except to the configured provider endpoint. Never log
  raw image bytes.
- Platforms: `.iOS(.v17)`, `.macOS(.v14)` (from existing `Package.swift`).
- Test framework: **Swift Testing** (`@Suite`, `@Test`, `#expect`), matching existing tests.
- **Provider model IDs and pricing move fast.** Treat every default model string and every
  cost figure in this plan as *verify-at-build-time*. Centralize them (see Task A6) so they are
  changed in exactly one place.

---

## File Structure

**New files (`Sources/SwiftAIKitImage/`):**
- `ImageServiceProtocol.swift` — the provider contract (actor).
- `ImageServiceRouter.swift` — `@MainActor @Observable` router with fallback.
- `Models/ImageProviderType.swift` — extensible `RawRepresentable` struct + known constants.
- `Models/ImageRequest.swift` — prompt, aspect, size, purpose, reference images.
- `Models/ImageResult.swift` — image bytes, mime type, provider, model, cost estimate.
- `Providers/GeminiImageProvider.swift` — Google Nano Banana via the Gemini API (actor).
- `Providers/OpenAIImageProvider.swift` — OpenAI GPT-Image via the Images API (actor).
- `Providers/SVGFallbackProvider.swift` — decoupled SVG generator (actor).
- `Configuration/ImageBYOKConfiguration.swift` — key-account names + default endpoints/models.
- `Configuration/ImageProviderConfigurator.swift` — `SecretStore`-backed factory (lazy key).
- `Pricing/ImagePricing.swift` — single source of truth for per-image cost estimates.

**Modified files (package):**
- `Package.swift` — add `SwiftAIKitImage` library product + target (dep: `SwiftAIKit`) and a
  `SwiftAIKitImageTests` test target.

**New tests (`Tests/SwiftAIKitImageTests/`):**
- `ImageServiceRouterTests.swift` — active provider, fallback order, error propagation.
- `GeminiResponseParsingTests.swift` — decode base64 image payload; error bodies.
- `OpenAIResponseParsingTests.swift` — decode `b64_json`; error bodies.
- `SVGFallbackProviderTests.swift` — well-formed pass, malformed → repair → template.
- `ImageProviderTypeTests.swift` — raw-value round-trip; app-defined custom type.

---

## Design detail

### `ImageProviderType` (extensible)
```swift
public struct ImageProviderType: RawRepresentable, Hashable, Sendable, Codable, Identifiable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }

    public static let geminiNanoBanana = ImageProviderType(rawValue: "geminiNanoBanana")
    public static let openAIImage      = ImageProviderType(rawValue: "openAIImage")
    public static let svgFallback      = ImageProviderType(rawValue: "svgFallback")
    // Apps may define their own, e.g. `.init(rawValue: "paperBanana")`.

    public var displayName: String { … }   // switch on known rawValues, else rawValue
}
```

### `ImageServiceProtocol`
```swift
public protocol ImageServiceProtocol: Actor {
    var providerType: ImageProviderType { get }
    /// Configured with a way to supply credentials (or none needed). Does NOT read the
    /// Keychain — mirror `AnthropicProvider.isAvailable`; validate the key at request time.
    var isAvailable: Bool { get }
    func generate(_ request: ImageRequest) async throws -> ImageResult
}
```

### `ImageRequest` / `ImageResult`
```swift
public struct ImageRequest: Sendable {
    public var prompt: String
    public var aspect: AspectRatio        // .square1x1, .wide16x9, .portrait9x16, .custom(w,h)
    public var size: ImageSize            // pixel target; provider clamps to supported sizes
    public var purpose: ImagePurpose      // .hero, .figure  (hint for the caller/adapters)
    public var referenceImages: [Data]    // optional style refs (providers that support them)
    public init(prompt: String, aspect: AspectRatio = .wide16x9,
                size: ImageSize = .init(width: 1200, height: 630),
                purpose: ImagePurpose = .hero, referenceImages: [Data] = [])
}

public struct ImageResult: Sendable {
    public let data: Data                 // PNG bytes, or UTF-8 SVG for the fallback
    public let mimeType: String           // "image/png" | "image/svg+xml"
    public let provider: ImageProviderType
    public let model: String?
    public let costEstimateUSD: Double?   // from ImagePricing; nil if unknown
}
```

### `ImageServiceRouter` (mirror `AIServiceRouter`)
- `@MainActor @Observable final class`. `init(defaultProvider:defaultsKey:)`,
  `configure(_:with:)`, `activeProviderType` (persisted to `UserDefaults`), `fallbackOrder`,
  `func generate(_:) async throws -> ImageResult`, and `generate(using:_:)`.
- `generate` tries the active provider; on `AIError.providerUnavailable`/`.notConfigured`
  (or a provider that reports `isAvailable == false`), walk `fallbackOrder`. Typical config:
  `fallbackOrder = [.geminiNanoBanana, .svgFallback]`, guaranteeing a result.
- Reuse `AIError` (no new error type) so callers switch on the same cases as text.

### `GeminiImageProvider` (Nano Banana)
- `public actor` conforming to `ImageServiceProtocol`. `Configuration(apiKey:endpoint:model:
  apiKeyResolver:)` mirroring `AnthropicProvider` (lazy `@Sendable` resolver; `isAvailable`
  does NOT call it). Default endpoint the Gemini API base; default model a Nano Banana image
  model (**verify current ID** — e.g. Nano Banana 2 Lite for cost). POST the image-generation
  request, decode the returned inline base64 image data → PNG `Data`. Map non-200/blocked →
  `AIError.requestFailed`/`.contentFiltered`.
- **VERIFY AT BUILD:** exact endpoint path, request JSON shape, response field holding image
  bytes, and safety-block signaling. Keep the wire mapping in one private method.

### `OpenAIImageProvider` (GPT-Image)
- `public actor`, same shape. `Configuration(apiKey:endpoint:model:organizationID:apiKeyResolver:)`
  mirroring `OpenAIProvider`. Default endpoint `https://api.openai.com`, model `gpt-image-1`
  (**verify**). POST `/v1/images/generations`, decode `data[0].b64_json` → PNG `Data`.

### `SVGFallbackProvider` (decoupled, dependency-free)
- `public actor`. Does NOT import the text router. Instead its init takes an injected
  `@Sendable (_ prompt: String, _ systemPrompt: String?) async throws -> String` closure — the
  consuming app passes a shim over `AIServiceRouter.complete().content`. This keeps
  `SwiftAIKitImage` decoupled from text specifics while still producing model-authored SVG.
- On `generate`: ask the closure for a self-contained `<svg …>` (viewBox from the request
  size), validate with `XMLDocument` (repair-retry once with the parse error, then fall back to
  a bundled template constant), return `mimeType: "image/svg+xml"`, `costEstimateUSD: 0`.
- `isAvailable` is always `true`.

### `ImageProviderConfigurator` + `ImageBYOKConfiguration`
- Mirror `ProviderConfigurator` / `BYOKConfiguration`. `ImageBYOKConfiguration` holds Keychain
  account names (`geminiImageAPIKey`, `openAIImageAPIKey`), default endpoints, default models,
  and the `UserDefaults` provider key. `configureGemini(router:secretStore:config:)` and
  `configureOpenAIImage(...)` build providers with a **lazy** `apiKeyResolver` capturing the
  `SecretStore` — no Keychain read at configure time (same rule as Anthropic).

### `ImagePricing`
- One `enum`/table mapping `(ImageProviderType, model, size-bucket) -> USD/image`. Used to fill
  `ImageResult.costEstimateUSD`. Documented as approximate + verify-at-build. Unknown → `nil`.

---

## PHASE A — SwiftAIKitImage target

### Task A1: Package wiring
- [ ] Add `SwiftAIKitImage` library product + target to `Package.swift` (path
  `Sources/SwiftAIKitImage`, dependency `["SwiftAIKit"]`, `.swiftLanguageMode(.v6)`).
- [ ] Add `SwiftAIKitImageTests` test target (dependency `["SwiftAIKitImage"]`).
- [ ] Empty target builds: `swift build`.

### Task A2: Models
- [ ] `ImageProviderType` (RawRepresentable struct + known constants + `displayName`).
- [ ] `ImageRequest`, `ImageResult`, `AspectRatio`, `ImageSize`, `ImagePurpose` (all `Sendable`).
- [ ] `ImageProviderTypeTests`: raw-value round-trip; an app-defined custom type is usable.

### Task A3: Protocol + Router
- [ ] `ImageServiceProtocol`.
- [ ] `ImageServiceRouter` (register/active/fallback/generate), reusing `AIError`.
- [ ] `ImageServiceRouterTests` with a stub provider: active path, fallback on unavailable,
  error propagation when no fallback succeeds. (Register a stub via `configure(_:with:)`.)

### Task A4: Gemini + OpenAI providers
- [ ] `GeminiImageProvider` (+ `Configuration`, lazy resolver, wire mapping in one method).
- [ ] `OpenAIImageProvider` (+ `Configuration`).
- [ ] `GeminiResponseParsingTests`, `OpenAIResponseParsingTests` against **captured sample JSON**
  (success + error + safety-block), decoding via injected `URLSession`/fixture, not live calls.

### Task A5: SVG fallback
- [ ] `SVGFallbackProvider` with the injected text closure; `XMLDocument` validation +
  repair-retry + bundled template.
- [ ] `SVGFallbackProviderTests`: well-formed passes; malformed triggers one repair; second
  failure returns the template; `costEstimateUSD == 0`.

### Task A6: Configuration + pricing
- [ ] `ImageBYOKConfiguration`, `ImageProviderConfigurator` (lazy `SecretStore` resolvers).
- [ ] `ImagePricing` table; wire `costEstimateUSD` in each provider.
- [ ] Readiness-style test using `InMemorySecretStore` (key present/absent → `isAvailable`).

### Task A7: Docs
- [ ] Update `CLAUDE.md`: add `SwiftAIKitImage` to the architecture map + a "Consuming images"
  snippet (configure router, `generate`, fallback order). Note the verify-at-build caveats.

---

## Acceptance criteria
- `swift build` and `swift test` pass; new tests are deterministic and offline (no live API).
- A consumer can: configure a `KeychainSecretStore`, call
  `ImageProviderConfigurator.configureGemini(router:secretStore:)`, set
  `router.fallbackOrder = [.geminiNanoBanana, .svgFallback]`, and get an `ImageResult` from
  `try await router.generate(.init(prompt: "…"))` — with the SVG fallback covering a missing key.
- No SwiftUI import in the target; no external dependencies; no secret/byte logging.
- App-level providers (PaperBanana) can conform to `ImageServiceProtocol` and register on the
  router without package changes.

## Out of scope (app-level, not this package)
- The **PaperBanana** adapter (Python subprocess/MCP) — lives in Between Fields Studio; it just
  conforms to `ImageServiceProtocol` with `providerType = .init(rawValue: "paperBanana")`.
- Any image preview UI (belongs in the app, or a future `SwiftAIKitImageUI` mirroring
  `SwiftAIKitUI`).
- Streaming/progressive image results.
