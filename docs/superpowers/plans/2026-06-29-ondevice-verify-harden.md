# SwiftAIKit On-Device Provider — Verify & Harden (Phase A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make SwiftAIKit's on-device (Apple Intelligence / FoundationModels) provider genuinely robust — honor `maxTokens`, never silently return empty, send a clean prompt, and prove the live model path works on this Mac via an availability-guarded integration test.

**Architecture:** Small, surgical changes to the existing `OnDeviceProvider` actor. Extract the prompt-building into a pure, unit-testable helper; build `GenerationOptions` from `maxTokens`; guard empty responses; add a live integration test guarded on `SystemLanguageModel` availability so it runs on AI-capable Macs and skips cleanly elsewhere. (Phase B — `@Generable` guided generation for structured JSON — is a SEPARATE later plan; do NOT start it here.)

**Tech Stack:** Swift 6, FoundationModels (macOS 26+), Swift Testing.

## Global Constraints

- **Swift 6**, strict concurrency. SwiftAIKit package floor is `macOS(.v14)` / `iOS(.v17)`; all FoundationModels code stays behind `#if canImport(FoundationModels)` + `@available(macOS 26.0, iOS 26.0, *)` so the package still compiles on macOS 14–25.
- **Zero third-party dependencies.** Apple frameworks only. Do NOT add a swift-testing package.
- **Build/test under the Xcode toolchain** (CommandLineTools lacks the bundled Testing module AND the macOS 26 SDK): `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` (run from the SwiftAIKit repo root). For a build-only check: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`.
- House style: 4-space indent, `// MARK: -` sections, actors for providers, no force-unwraps in provider code.
- Preserve the existing public API of `OnDeviceProvider`/`AIServiceProtocol` — these are surgical internal changes plus additive tests. Do not change `complete(messages:systemPrompt:maxTokens:)`'s signature.
- Git: branch `feature/ondevice-harden`; commit per task; end messages with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

**Confirmed FoundationModels API (verified against `MacOSX26.4.sdk` swiftinterface — use these exact shapes):**
- `LanguageModelSession(model:tools:instructions: String?)` convenience init exists.
- `func respond(to prompt: String, options: GenerationOptions = GenerationOptions()) async throws -> LanguageModelSession.Response<String>`
- `Response<Content>` has `public let content: Content` (so `.content` is a `String` for the text overload).
- `GenerationOptions(sampling: SamplingMode? = nil, temperature: Double? = nil, maximumResponseTokens: Int? = nil)`; properties `temperature: Double?`, `maximumResponseTokens: Int?`.
- `SystemLanguageModel.default.availability` → enum `Availability` with `case available` (+ `.unavailable(...)` reasons).

**Existing code (consume/modify, do not guess — read the file):** `Sources/SwiftAIKit/Providers/OnDeviceProvider.swift` — actor `OnDeviceProvider`, `complete(messages:systemPrompt:maxTokens:)` (~line 40), `completeWithFoundationModels(messages:systemPrompt:)` (~lines 76–113), `availabilityReason(_:)` (~lines 118–127), `AIError` (in `Models/`), `AIMessage`/`AIRole`, `AIResponse(content:usage:model:finishReason:)`.

---

## Task 1: Honor maxTokens, clean prompt, guard empty (with pure-helper unit tests)

**Files:**
- Modify: `Sources/SwiftAIKit/Providers/OnDeviceProvider.swift`
- Test: `Tests/SwiftAIKitTests/OnDeviceProviderTests.swift` (create if absent; else add to the existing on-device test file)

**Interfaces:**
- Produces (pure, testable WITHOUT the model — define as `static`/non-isolated so tests reach them on any OS):
  - `static func OnDeviceProvider.buildPrompt(from messages: [AIMessage]) -> String` — if `messages` is exactly one `.user` message, returns its `content` verbatim (no `"User: "` prefix); otherwise returns the role-labeled join (`"System: …\nUser: …\nAssistant: …"`).
  - `static func OnDeviceProvider.generationOptions(maxTokens: Int) -> GenerationOptions` — **only compiled under `#if canImport(FoundationModels)` + `@available`**; returns `GenerationOptions(maximumResponseTokens: maxTokens > 0 ? maxTokens : nil)`. (Because this is availability-gated, unit-test `buildPrompt` directly; verify `generationOptions` via the integration test in Task 2.)
- Behavior change: `completeWithFoundationModels` builds the prompt via `buildPrompt`, calls `session.respond(to: prompt, options: Self.generationOptions(maxTokens: maxTokens))`, and after getting `response.content` throws `AIError.requestFailed("On-device model returned an empty response.")` if the trimmed content is empty.
- Note: `complete(...)` must thread `maxTokens` into `completeWithFoundationModels` — change that private method's signature to `completeWithFoundationModels(messages:systemPrompt:maxTokens:)`.

- [ ] **Step 1: Write the failing test (pure prompt helper)**

In `Tests/SwiftAIKitTests/OnDeviceProviderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OnDeviceProviderPromptTests 2>&1 | tail -20`
Expected: FAIL — `buildPrompt` not found.

- [ ] **Step 3: Implement the changes**

In `OnDeviceProvider.swift`:

(a) Add the pure prompt helper (non-isolated `static`, available on all OS — no FoundationModels types):

```swift
    // MARK: - Prompt building (pure, testable on any OS)

    /// A single user turn is sent verbatim (the common case); multi-message
    /// histories are role-labeled. Kept pure so it is unit-testable without
    /// the on-device model.
    static func buildPrompt(from messages: [AIMessage]) -> String {
        if messages.count == 1, messages[0].role == .user {
            return messages[0].content
        }
        return messages.map { msg in
            switch msg.role {
            case .system:    return "System: \(msg.content)"
            case .user:      return "User: \(msg.content)"
            case .assistant: return "Assistant: \(msg.content)"
            }
        }.joined(separator: "\n")
    }
```

(b) Inside the `#if canImport(FoundationModels)` block, add the options builder and rewrite `completeWithFoundationModels` to take `maxTokens`, pass options, and guard empty:

```swift
    @available(macOS 26.0, iOS 26.0, *)
    static func generationOptions(maxTokens: Int) -> GenerationOptions {
        GenerationOptions(maximumResponseTokens: maxTokens > 0 ? maxTokens : nil)
    }

    @available(macOS 26.0, iOS 26.0, *)
    private func completeWithFoundationModels(
        messages: [AIMessage],
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> AIResponse {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw AIError.providerUnavailable(availabilityReason(model.availability))
        }

        let session = LanguageModelSession(instructions: systemPrompt ?? "")
        let prompt = Self.buildPrompt(from: messages)

        do {
            let response = try await session.respond(to: prompt, options: Self.generationOptions(maxTokens: maxTokens))
            let content = response.content
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIError.requestFailed("On-device model returned an empty response.")
            }
            return AIResponse(content: content, usage: nil, model: "apple-intelligence-on-device", finishReason: .stop)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.requestFailed(error.localizedDescription)
        }
    }
```

(c) Update the call site in `complete(...)` to pass `maxTokens`:

```swift
            return try await completeWithFoundationModels(messages: messages, systemPrompt: systemPrompt, maxTokens: maxTokens)
```

(Read the current `complete(...)` to match its exact `if #available` structure; only thread `maxTokens` through — do not change its public signature or the `#else`/unavailable throw.)

- [ ] **Step 4: Run to verify the pure tests pass + full build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OnDeviceProviderPromptTests 2>&1 | tail -20`
Expected: PASS.
Then full build to confirm the FoundationModels block still compiles against the macOS 26 SDK:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build 2>&1 | tail -15` → no errors.
Then the whole suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | tail -15` → all prior tests still pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(on-device): honor maxTokens via GenerationOptions, clean single-turn prompt, guard empty response

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Live availability-guarded integration test (prove the real path)

**Files:**
- Test: `Tests/SwiftAIKitTests/OnDeviceProviderTests.swift` (add to the file from Task 1)

**Interfaces:**
- Consumes: `OnDeviceProvider().complete(messages:systemPrompt:maxTokens:)`; `SystemLanguageModel` (FoundationModels).

- [ ] **Step 1: Write the integration test**

This test ACTUALLY calls the on-device model when this machine has Apple Intelligence available, and skips cleanly otherwise (older OS, no AI hardware, or a test process that can't reach the model). Append to `OnDeviceProviderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it and RECORD what happened**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OnDeviceProviderLiveTests 2>&1 | tail -30`
Expected: PASS. **In the report, state explicitly which branch executed** — did it hit the live model (look for the `LIVE on-device response:` line in output) or did it SKIP (and why — which availability reason)? This is the key verification deliverable: it tells us whether the on-device path genuinely works from a test process on this Mac, or whether only the GUI app (with full app context) can reach the model.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test(on-device): availability-guarded live FoundationModels integration test

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Phase A "verify + harden"):**
- Honor `maxTokens` → Task 1 (`generationOptions` + `respond(to:options:)`). ✓
- Don't silently return empty → Task 1 (empty-content guard throws `AIError.requestFailed`). ✓
- Clean prompt for the single-turn case (all CareerPilot calls) → Task 1 (`buildPrompt`). ✓
- Prove the live path on this Mac → Task 2 (availability-guarded integration test that records live-vs-skip). ✓
- Verify the real API → DONE pre-plan (swiftinterface confirms `response.content`, `respond(to:options:)`, `GenerationOptions`, `.available`); the plan's code uses exactly those shapes; Task 1's `swift build` re-confirms compilation against the macOS 26 SDK. ✓
- **Out of scope (Phase B, separate plan):** `@Generable` guided generation for structured JSON (extraction/ranking reliability). **Not started here.**
- **Noted, not in this plan (CareerPilot-side follow-ups):** long-input truncation in `ResumeExtractionService`; the privacy-safe no-auto-fallback for extraction is ALREADY the case (`router.fallbackOrder` is empty), so no change needed — document it.

**Placeholder scan:** none — all code is complete. The one genuine unknown (can a CLI `swift test` process reach Apple Intelligence?) is handled by design: the test runs live if available, skips with a printed reason otherwise, and Task 2 Step 2 requires reporting which occurred.

**Type consistency:** `buildPrompt(from:) -> String`, `generationOptions(maxTokens:) -> GenerationOptions`, `completeWithFoundationModels(messages:systemPrompt:maxTokens:)`, `AIError.requestFailed`/`.providerUnavailable`, `AIResponse(content:usage:model:finishReason:)`, `AIMessage(role:content:)`, `AIRole.system/.user/.assistant` — all match the existing SwiftAIKit API. FoundationModels shapes match the verified swiftinterface.

**Watch items for the implementer:**
- `buildPrompt` and the pure tests must compile on ANY macOS (they touch no FoundationModels types) — keep `buildPrompt` OUTSIDE the `#if canImport(FoundationModels)` block; keep `generationOptions` INSIDE it.
- Read the current `complete(...)` `if #available` structure before editing — only thread `maxTokens` through and rewrite the private method; do not alter the public signature or the `#else` unavailable-throw.
- If the live test SKIPs because the CLI process can't reach the model, that is a valid (and important) finding — NOT a failure. Report it so we know GUI-level verification is the real proof.
