# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

SwiftAIKit is a zero-dependency Swift Package that provides a protocol-based abstraction layer for AI service providers. It enables Swift apps to switch between on-device Apple Intelligence, Anthropic Claude, and OpenAI-compatible APIs through a unified interface.

**Key philosophy**: Zero external Swift dependencies. Uses only Apple frameworks (Foundation, FoundationModels) and raw `URLSession` for API calls. Designed to be embedded in apps that share this same philosophy.

## Architecture

```
Sources/SwiftAIKit/
├── AIServiceProtocol.swift              # Core protocol all providers implement
├── AIServiceRouter.swift                # @Observable router — main entry point for apps
├── Models/
│   ├── AIMessage.swift                  # Conversation message (role + content)
│   ├── AIResponse.swift                 # Completion result (content + usage + metadata)
│   ├── AIError.swift                    # Error types
│   └── AIProvider.swift                 # Provider type enum (onDevice, anthropic, openAI)
├── Providers/
│   ├── AnthropicProvider.swift          # Anthropic Messages API (actor)
│   ├── OpenAIProvider.swift             # OpenAI Chat Completions API (actor)
│   └── OnDeviceProvider.swift           # Apple Intelligence / FoundationModels (actor)
└── Configuration/
    └── ProviderConfigurator.swift       # Convenience factory for UserDefaults-based setup
```

```
Sources/SwiftAIKitImage/
├── ImageServiceProtocol.swift           # Core protocol all image providers implement (Actor)
├── ImageServiceRouter.swift             # @Observable router — main entry point for image requests
├── Models/
│   ├── ImageProviderType.swift          # Extensible RawRepresentable provider-type identifier
│   ├── ImageRequest.swift               # Request struct (prompt, aspect, size, purpose, reference images)
│   └── ImageResult.swift                # Result struct (data, mimeType, provider, model, cost estimate)
├── Providers/
│   ├── GeminiImageProvider.swift        # Gemini `generateContent` image endpoint (actor)
│   ├── OpenAIImageProvider.swift        # OpenAI `/v1/images/generations` endpoint (actor)
│   └── SVGFallbackProvider.swift        # Dependency-free SVG fallback (injected text closure)
├── Configuration/
│   ├── ImageBYOKConfiguration.swift     # Keychain accounts, UserDefaults keys, default models/endpoints
│   └── ImageProviderConfigurator.swift  # Convenience factory wiring SecretStore + UserDefaults into providers
└── Pricing/
    └── ImagePricing.swift               # Per-image USD cost lookup table, keyed by provider/model/size
```

### Core Workflow

1. **App creates an `AIServiceRouter`** — the main entry point
2. **App registers providers** via `router.configure(.anthropic, with: provider)`
3. **App sets `router.activeProviderType`** — persisted in UserDefaults
4. **App calls `router.complete(messages:systemPrompt:maxTokens:)`**
5. **Router delegates to the active provider's `complete()` method**
6. **Provider handles transport, auth, and response parsing**
7. **App receives a unified `AIResponse`**

### Key Design Patterns

- **Protocol-based**: `AIServiceProtocol` is the contract. Any new provider just conforms to it.
- **Actor isolation**: All providers are actors for thread safety.
- **`@Observable` router**: The router is `@MainActor @Observable` so SwiftUI views can observe `activeProviderType` changes.
- **Domain-agnostic**: The package knows nothing about diagrams, nutrition, fitness, etc. Apps provide system prompts and parse response content themselves.
- **Unified response type**: `AIResponse` is the common return type across all providers, with optional metadata (usage, model, finish reason).

## Coding Standards

- **Swift 6.0** with strict concurrency enabled
- **No external dependencies** — only Apple frameworks and raw URLSession
- **4-space indentation**, 120-char soft line limit
- **`public`** for all API surface types and methods
- **`private`** for implementation details
- **Trailing commas** in multi-line collections
- **`// MARK: -`** sections to organize code within files

## Building

```bash
swift build
swift test
```

## Adding a New Provider

1. Create a new file in `Providers/` — e.g., `GroqProvider.swift`
2. Define an actor that conforms to `AIServiceProtocol`
3. Add a new case to `AIProviderType` in `Models/AIProvider.swift`
4. Optionally add setup to `ProviderConfigurator` for UserDefaults convenience
5. That's it — the router handles the rest via the protocol

## Consuming This Package

### As a local dependency (recommended during development)

In your app's `Package.swift` or Xcode project:

```swift
// Package.swift
dependencies: [
    .package(path: "../SwiftAIKit"),
]
```

Or in Xcode: File → Add Package Dependencies → Add Local → select the SwiftAIKit folder.

### Integration pattern

```swift
import SwiftAIKit

@main
struct MyApp: App {
    @State private var aiRouter = AIServiceRouter(defaultProvider: .anthropic)

    init() {
        ProviderConfigurator.configureAll(
            router: aiRouter,
            anthropicKeyDefault: "myApp_anthropicKey"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(aiRouter)
        }
    }
}
```

### Consuming images

`SwiftAIKitImage` is a separate library target (depends on `SwiftAIKit`, still zero external
dependencies) providing the same protocol/router/configurator shape as the core package, but for
image generation instead of text completion.

```swift
import SwiftAIKit
import SwiftAIKitImage

let aiRouter = AIServiceRouter(defaultProvider: .anthropic)
let imageRouter = ImageServiceRouter()
let secretStore = KeychainSecretStore(service: "com.myapp")

ImageProviderConfigurator.configureAll(
    router: imageRouter,
    secretStore: secretStore,
    svgFallbackComplete: { prompt, systemPrompt in
        try await aiRouter.complete(
            messages: [AIMessage(role: .user, content: prompt)],
            systemPrompt: systemPrompt
        ).content
    }
)

imageRouter.fallbackOrder = [.geminiNanoBanana, .svgFallback]

let result = try await imageRouter.generate(.init(prompt: "a red panda in a garden"))
// result.data / result.mimeType / result.provider / result.model / result.costEstimateUSD
```

`ImageProviderConfigurator.configureAll` wires all three providers (Gemini, OpenAI image, SVG
fallback) at once. To wire just one provider (e.g. only Gemini, skipping OpenAI), call
`ImageProviderConfigurator.configureGemini(router:secretStore:config:session:)` directly and
register `SVGFallbackProvider(complete:)` yourself:

```swift
ImageProviderConfigurator.configureGemini(router: imageRouter, secretStore: secretStore)
imageRouter.configure(.svgFallback, with: SVGFallbackProvider(complete: { prompt, systemPrompt in
    try await aiRouter.complete(
        messages: [AIMessage(role: .user, content: prompt)],
        systemPrompt: systemPrompt
    ).content
}))
```

The SVG fallback never touches `SwiftAIKit` directly — it takes an injected `@Sendable` text
closure so `SwiftAIKitImage` stays decoupled from any particular text provider. The closure is
typically a thin shim over `AIServiceRouter.complete(...).content`, as above. Because
`SVGFallbackProvider.isAvailable` is unconditionally `true`, it's meant to sit last in
`fallbackOrder` — the guaranteed-success end of the chain.

### Verify-at-build caveats (image target)

- **Model IDs and prices move fast.** Don't trust defaults baked into this doc or the source
  without re-checking the provider's docs at build time.
- **Centralized in one place each**: default model IDs and endpoints live in
  `ImageBYOKConfiguration` (`geminiDefaultModel`, `openAIDefaultModel`, etc.) and mirrored in each
  provider's `Configuration` initializer default; per-image USD estimates live in `ImagePricing`.
  Update both the `ImageBYOKConfiguration` default and the provider's `Configuration` default
  together if a model ID changes.
- **Gemini uses the `generateContent` surface**, not the newer Interactions API — see
  `GeminiImageProvider`'s doc comment for the exact REST reference pages checked. Re-verify
  request/response shapes against `https://ai.google.dev/api/generate-content` and the live
  Discovery document if Google ships an Interactions-API-based image path later.
- **`gpt-image-1` pricing is cited from OpenAI's legacy per-image table** (`ImagePricing`'s doc
  comment), because `gpt-image-1` no longer appears on OpenAI's token-based pricing page at all —
  only the newer `gpt-image-2`/`gpt-image-1.5`/`gpt-image-1-mini` variants do. If OpenAI removes
  the legacy table or migrates `gpt-image-1` itself to token billing, `ImagePricing`'s
  `openAIPriceUSD` needs a rewrite, not just a number change.

### Extensibility: app-defined providers

Unlike `AIProviderType` (a closed enum), `ImageProviderType` is a `RawRepresentable` struct. Apps
can define their own provider types and register a conforming actor on the router without any
changes to this package:

```swift
extension ImageProviderType {
    static let paperBanana = ImageProviderType(rawValue: "paperBanana")
}

actor PaperBananaProvider: ImageServiceProtocol {
    let providerType: ImageProviderType = .paperBanana
    var isAvailable: Bool { /* ... */ true }
    func generate(_ request: ImageRequest) async throws -> ImageResult { /* ... */ }
}

imageRouter.configure(.paperBanana, with: PaperBananaProvider())
```

This is how the app-level PaperBanana adapter (a Python subprocess/MCP bridge, out of scope for
this package) plugs in — it just conforms to `ImageServiceProtocol` and registers itself.

## Important Notes

- **FoundationModels requires macOS 26+ / iOS 26+** — the on-device provider uses `#if canImport` and `@available` guards to compile on earlier targets
- **API keys** are read from UserDefaults by `ProviderConfigurator`, but apps can also construct providers directly with explicit keys
- **The package never logs or transmits API keys** except to the configured endpoint
- **OpenAI provider works with any compatible endpoint** — Ollama, LM Studio, vLLM, Together AI, Groq, etc. Local endpoints don't require an API key.
- **`SwiftAIKitImage` has no SwiftUI import and no external dependencies** — same zero-dependency philosophy as the core target, just for image generation instead of text
- **`SwiftAIKitImage` API keys are also read lazily** — `ImageProviderConfigurator` hands each provider an `apiKeyResolver` closure over a `SecretStore`; the Keychain is read at request time, never at configure time
- **`SwiftAIKitImage` never logs secrets or image bytes**
