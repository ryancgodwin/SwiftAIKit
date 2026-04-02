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

## Important Notes

- **FoundationModels requires macOS 26+ / iOS 26+** — the on-device provider uses `#if canImport` and `@available` guards to compile on earlier targets
- **API keys** are read from UserDefaults by `ProviderConfigurator`, but apps can also construct providers directly with explicit keys
- **The package never logs or transmits API keys** except to the configured endpoint
- **OpenAI provider works with any compatible endpoint** — Ollama, LM Studio, vLLM, Together AI, Groq, etc. Local endpoints don't require an API key.
