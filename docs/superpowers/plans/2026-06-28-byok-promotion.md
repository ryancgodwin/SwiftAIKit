# SwiftAIKit BYOK Promotion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the bring-your-own-key (BYOK) configuration element — Keychain-backed
secret storage, provider-readiness classification, and the settings UI — out of DiagramDesigner
and into SwiftAIKit so CareerPilot and DiagramDesigner share one implementation.

**Architecture:** Add Keychain/secret + readiness logic to the existing Foundation-only
`SwiftAIKit` core behind a `SecretStore` protocol (injectable, with an in-memory test double),
and add a **new SwiftUI target `SwiftAIKitUI`** for the reusable settings view so the core stays
dependency-free. DiagramDesigner is then migrated to consume the shared code and delete its
local copies.

**Tech Stack:** Swift 6.0 (strict concurrency), SwiftPM, Foundation + Security (core),
SwiftUI + LocalAuthentication (`SwiftAIKitUI`), Swift Testing (`import Testing`).

## Global Constraints

- **Swift 6.0** with strict concurrency (`.swiftLanguageMode(.v6)`), copied from the existing
  `Package.swift`.
- **Zero external dependencies** — only Apple frameworks (Foundation, Security, SwiftUI,
  LocalAuthentication, FoundationModels) and raw `URLSession`.
- **Core target `SwiftAIKit` must not import SwiftUI/LocalAuthentication** — UI lives only in
  the new `SwiftAIKitUI` target.
- **4-space indentation**, 120-char soft line limit, `public` for API surface, `private` for
  internals, `// MARK: -` section headers, trailing commas in multi-line collections.
- **Never log or transmit secret values** except to the configured provider endpoint.
- Platforms: `.iOS(.v17)`, `.macOS(.v14)` (from existing `Package.swift`). FoundationModels code
  guarded by `#if canImport(FoundationModels)` + `@available(macOS 26.0, iOS 26.0, *)`.
- Test framework: **Swift Testing** (`@Suite`, `@Test`, `#expect`), matching
  `Tests/SwiftAIKitTests/SwiftAIKitTests.swift`.

---

## File Structure

**New files (core — `Sources/SwiftAIKit/`):**
- `Configuration/SecretStore.swift` — `SecretStore` protocol + `InMemorySecretStore`.
- `Configuration/KeychainSecretStore.swift` — Keychain-backed `SecretStore` (service-scoped).
- `Configuration/BYOKConfiguration.swift` — key-name + defaults bundle shared by readiness/UI.
- `Configuration/ProviderReadiness.swift` — `ProviderReadiness` enum + `ProviderReadinessChecker`.

**Modified files (core):**
- `Configuration/ProviderConfigurator.swift` — add a `SecretStore`-backed Anthropic configure.

**New files (UI — `Sources/SwiftAIKitUI/`):**
- `AIProviderSettingsModel.swift` — `@MainActor @Observable` logic for the settings form (testable).
- `AIProviderSettingsView.swift` — thin SwiftUI view consuming the model.

**Modified files (package):**
- `Package.swift` — add `SwiftAIKitUI` library product + target; add `SwiftAIKitUITests` target.

**New tests:**
- `Tests/SwiftAIKitTests/SecretStoreTests.swift`
- `Tests/SwiftAIKitTests/ProviderReadinessTests.swift`
- `Tests/SwiftAIKitUITests/AIProviderSettingsModelTests.swift`

**Phase C (DiagramDesigner repo) — modified:**
- Delete `Services/KeychainStore.swift`, `Services/AIProviderReadiness.swift`.
- Replace the AI section of `Views/PreferencesView.swift` with `AIProviderSettingsView`.
- Update `DiagramDesignerApp.swift` (use shared `KeychainSecretStore` + `ProviderReadinessChecker`).
- `project.pbxproj` / Package pin — add `SwiftAIKitUI`, bump SwiftAIKit version, drop deleted files.

---

## PHASE A — SwiftAIKit core

### Task A1: `SecretStore` protocol + `InMemorySecretStore`

**Files:**
- Create: `Sources/SwiftAIKit/Configuration/SecretStore.swift`
- Test: `Tests/SwiftAIKitTests/SecretStoreTests.swift`

**Interfaces:**
- Produces: `protocol SecretStore` with `string(forKey:)`, `refreshedString(forKey:)`,
  `set(_:forKey:)`, `removeValue(forKey:)`; `final class InMemorySecretStore: SecretStore`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiftAIKitTests/SecretStoreTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SecretStore`
Expected: FAIL — `InMemorySecretStore` not defined / does not compile.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SwiftAIKit/Configuration/SecretStore.swift
import Foundation

/// Abstraction over secret storage (e.g. provider API keys).
///
/// Production uses `KeychainSecretStore`; tests use `InMemorySecretStore`.
/// `@MainActor` because the Keychain implementation caches per-launch reads and
/// is consumed from `@MainActor` UI/readiness code.
@MainActor
public protocol SecretStore: AnyObject {

    /// Read a secret, possibly served from a per-launch cache.
    func string(forKey key: String) -> String?

    /// Read fresh, bypassing any cache — for explicit, user-initiated reveals.
    func refreshedString(forKey key: String) -> String?

    /// Store (or replace) a value. An empty string removes the item, so
    /// "cleared the field" and "no secret" are the same state.
    func set(_ value: String, forKey key: String)

    /// Remove a stored secret.
    func removeValue(forKey key: String)
}

/// In-memory `SecretStore` for tests and previews. Not persistent.
@MainActor
public final class InMemorySecretStore: SecretStore {

    private var storage: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? { storage[key] }

    public func refreshedString(forKey key: String) -> String? { storage[key] }

    public func set(_ value: String, forKey key: String) {
        guard !value.isEmpty else {
            storage.removeValue(forKey: key)
            return
        }
        storage[key] = value
    }

    public func removeValue(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SecretStore`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftAIKit/Configuration/SecretStore.swift Tests/SwiftAIKitTests/SecretStoreTests.swift
git commit -m "feat: add SecretStore protocol + InMemorySecretStore"
```

---

### Task A2: `KeychainSecretStore`

Port DiagramDesigner's `KeychainStore` into the package, generalized: the service identifier is
injected (not hardcoded), and the per-launch cache is an instance member (not a static).

**Files:**
- Create: `Sources/SwiftAIKit/Configuration/KeychainSecretStore.swift`

**Interfaces:**
- Consumes: `SecretStore` (Task A1).
- Produces: `final class KeychainSecretStore: SecretStore` with `init(service: String)`.

- [ ] **Step 1: Write the implementation**

> Keychain access is environment-dependent (entitlements, ACL prompts) and not reliably unit-
> testable in SPM/CI, so this task has no automated test — the logic is identical to the
> InMemory store (covered by A1) plus `Security` transport, and is integration-verified in
> Phase C. Verification here is "compiles + builds."

```swift
// Sources/SwiftAIKit/Configuration/KeychainSecretStore.swift
import Foundation
import Security
import os

/// Keychain-backed `SecretStore`. Stores generic-password items scoped to a
/// service identifier supplied at init. Values are UTF-8 strings. Never logs values.
///
/// Reads are cached for the lifetime of the launch: on the legacy file-based
/// keychain, every `SecItem` call against an item whose ACL doesn't trust the
/// current binary (routine in development, where each rebuild is ad-hoc signed)
/// raises a password prompt — the cache caps that at one prompt per launch.
@MainActor
public final class KeychainSecretStore: SecretStore {

    private let service: String
    private let logger: Logger

    /// Per-launch cache. The inner optional distinguishes "cached: no item"
    /// from "not yet read".
    private var cache: [String: String?] = [:]

    /// - Parameter service: the Keychain service identifier, typically the app
    ///   bundle id (e.g. `"com.blazepascal.CareerPilot"`).
    public init(service: String) {
        self.service = service
        self.logger = Logger(subsystem: service, category: "Keychain")
    }

    public func string(forKey key: String) -> String? {
        if let cached = cache[key] { return cached }
        return readThroughCache(forKey: key)
    }

    public func refreshedString(forKey key: String) -> String? {
        readThroughCache(forKey: key)
    }

    private func readThroughCache(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain read failed for \(key, privacy: .public): \(status)")
            }
            cache[key] = String?.none
            return nil
        }
        let value = String(data: data, encoding: .utf8)
        cache[key] = value
        return value
    }

    public func set(_ value: String, forKey key: String) {
        guard !value.isEmpty else {
            removeValue(forKey: key)
            return
        }
        guard let data = value.data(using: .utf8) else { return }
        cache[key] = value

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let update: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("Keychain write failed for \(key, privacy: .public): \(status)")
        }
    }

    public func removeValue(forKey key: String) {
        cache[key] = String?.none
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Keychain delete failed for \(key, privacy: .public): \(status)")
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftAIKit/Configuration/KeychainSecretStore.swift
git commit -m "feat: add KeychainSecretStore (service-scoped, port from DiagramDesigner)"
```

---

### Task A3: `BYOKConfiguration`

A small value type bundling the UserDefaults key names, the secret account key, and the
endpoint/model defaults — shared by the readiness checker and the settings UI so the strings
never diverge.

**Files:**
- Create: `Sources/SwiftAIKit/Configuration/BYOKConfiguration.swift`
- Test: add to `Tests/SwiftAIKitTests/ProviderReadinessTests.swift` (created in A4); for now a
  standalone check.

**Interfaces:**
- Produces: `struct BYOKConfiguration: Sendable` with fields
  `providerDefaultsKey`, `apiKeyAccount`, `endpointDefaultsKey`, `modelDefaultsKey`,
  `defaultEndpoint`, `defaultModel`, and a `static let `default``.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiftAIKitTests/BYOKConfigurationTests.swift
import Testing
@testable import SwiftAIKit

@Suite("BYOKConfiguration")
struct BYOKConfigurationTests {

    @Test("default config has anthropic.com endpoint and a sonnet model")
    func defaults() {
        let c = BYOKConfiguration.default
        #expect(c.defaultEndpoint == "https://api.anthropic.com")
        #expect(c.defaultModel.contains("claude"))
        #expect(c.apiKeyAccount == "anthropicAPIKey")
        #expect(c.providerDefaultsKey == "aiProvider")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BYOKConfiguration`
Expected: FAIL — `BYOKConfiguration` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SwiftAIKit/Configuration/BYOKConfiguration.swift
import Foundation

/// Names and defaults for a bring-your-own-key Anthropic setup. Shared by
/// `ProviderReadinessChecker` and the `SwiftAIKitUI` settings view so key
/// strings and defaults are defined exactly once.
public struct BYOKConfiguration: Sendable {

    /// UserDefaults key under which the active provider is persisted (the
    /// router's `defaultsKey`).
    public let providerDefaultsKey: String

    /// Keychain account name for the Anthropic API key.
    public let apiKeyAccount: String

    /// UserDefaults key for the Anthropic endpoint override.
    public let endpointDefaultsKey: String

    /// UserDefaults key for the Anthropic model override.
    public let modelDefaultsKey: String

    /// Endpoint used when no override is stored.
    public let defaultEndpoint: String

    /// Model used when no override is stored.
    public let defaultModel: String

    public init(
        providerDefaultsKey: String = "aiProvider",
        apiKeyAccount: String = "anthropicAPIKey",
        endpointDefaultsKey: String = "anthropicEndpoint",
        modelDefaultsKey: String = "anthropicModel",
        defaultEndpoint: String = "https://api.anthropic.com",
        defaultModel: String = "claude-sonnet-4-20250514"
    ) {
        self.providerDefaultsKey = providerDefaultsKey
        self.apiKeyAccount = apiKeyAccount
        self.endpointDefaultsKey = endpointDefaultsKey
        self.modelDefaultsKey = modelDefaultsKey
        self.defaultEndpoint = defaultEndpoint
        self.defaultModel = defaultModel
    }

    /// The conventional configuration (matches DiagramDesigner's historical keys).
    public static let `default` = BYOKConfiguration()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BYOKConfiguration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftAIKit/Configuration/BYOKConfiguration.swift Tests/SwiftAIKitTests/BYOKConfigurationTests.swift
git commit -m "feat: add BYOKConfiguration (shared key names + defaults)"
```

---

### Task A4: `ProviderReadiness` + `ProviderReadinessChecker`

Port DiagramDesigner's `AIProviderReadiness`/`AIProviderReadinessChecker` into the core,
parameterised by `SecretStore` + `BYOKConfiguration` instead of the app's hardcoded
`KeychainStore`/`UserDefaultsKeys`.

**Files:**
- Create: `Sources/SwiftAIKit/Configuration/ProviderReadiness.swift`
- Test: `Tests/SwiftAIKitTests/ProviderReadinessTests.swift`

**Interfaces:**
- Consumes: `SecretStore` (A1), `BYOKConfiguration` (A3), `AIServiceRouter`, `AIProviderType`,
  `ProviderConfigurator.configureAnthropic` (existing).
- Produces:
  - `enum ProviderReadiness: Equatable` — `.ready`, `.needsAnthropicKey`,
    `.onDeviceUnavailable(reason: String)`, with `var isReady: Bool` and
    `var userFacingMessage: String`.
  - `enum ProviderReadinessChecker` with
    `static func check(router:secretStore:config:) -> ProviderReadiness`,
    `static func isOnDeviceAvailable() -> Bool`,
    `static func smartDefaultProvider() -> AIProviderType`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiftAIKitTests/ProviderReadinessTests.swift
import Foundation
import Testing
@testable import SwiftAIKit

@MainActor
@Suite("ProviderReadiness")
struct ProviderReadinessTests {

    @Test("anthropic with no key reports needsAnthropicKey")
    func anthropicNoKey() {
        let router = AIServiceRouter(defaultProvider: .anthropic, defaultsKey: "test_provider_1")
        router.activeProviderType = .anthropic
        let store = InMemorySecretStore()
        let readiness = ProviderReadinessChecker.check(
            router: router, secretStore: store, config: .default
        )
        #expect(readiness == .needsAnthropicKey)
        #expect(readiness.isReady == false)
        #expect(readiness.userFacingMessage.isEmpty == false)
    }

    @Test("anthropic with a key reports ready")
    func anthropicWithKey() {
        let router = AIServiceRouter(defaultProvider: .anthropic, defaultsKey: "test_provider_2")
        router.activeProviderType = .anthropic
        let store = InMemorySecretStore()
        store.set("sk-ant-xyz", forKey: BYOKConfiguration.default.apiKeyAccount)
        let readiness = ProviderReadinessChecker.check(
            router: router, secretStore: store, config: .default
        )
        #expect(readiness == .ready)
        #expect(readiness.isReady)
    }

    @Test("ready state has an empty user-facing message")
    func readyMessageEmpty() {
        #expect(ProviderReadiness.ready.userFacingMessage.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderReadiness`
Expected: FAIL — `ProviderReadinessChecker` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/SwiftAIKit/Configuration/ProviderReadiness.swift
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the active AI provider is currently usable. The single source of
/// truth for "can the app make a request right now?" — synchronous and cheap,
/// safe to call from any view that gates behavior on AI availability.
public enum ProviderReadiness: Equatable, Sendable {

    /// Active provider is configured and credentials/model are available.
    case ready

    /// Active provider is `.anthropic` but no API key is stored.
    case needsAnthropicKey

    /// Active provider is `.onDevice` but FoundationModels is unavailable here.
    case onDeviceUnavailable(reason: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Short, user-facing message. Empty for `.ready`.
    public var userFacingMessage: String {
        switch self {
        case .ready:
            return ""
        case .needsAnthropicKey:
            return "Add your Claude API key in Settings to use cloud features."
        case .onDeviceUnavailable(let reason):
            return reason
        }
    }
}

/// Synchronous classifier for the active provider's readiness.
@MainActor
public enum ProviderReadinessChecker {

    /// Key last applied to the router's Anthropic provider this session, so the
    /// real key is injected lazily on first use rather than at launch.
    private static var lastAppliedAnthropicKey: String?

    /// Inspect the router's active provider and return its readiness. When the
    /// active provider is `.anthropic`, applies the stored key to the router if
    /// it changed.
    public static func check(
        router: AIServiceRouter,
        secretStore: SecretStore,
        config: BYOKConfiguration = .default
    ) -> ProviderReadiness {
        switch router.activeProviderType {
        case .anthropic:
            let key = secretStore.string(forKey: config.apiKeyAccount) ?? ""
            applyAnthropicKeyIfChanged(key, router: router, config: config)
            return key.isEmpty ? .needsAnthropicKey : .ready

        case .onDevice:
            return checkOnDeviceAvailability()

        case .openAI:
            // Not surfaced in v1 pickers; treat like Anthropic for gating.
            let key = secretStore.string(forKey: config.apiKeyAccount) ?? ""
            return key.isEmpty ? .needsAnthropicKey : .ready
        }
    }

    /// True if FoundationModels reports an available on-device model here.
    public static func isOnDeviceAvailable() -> Bool {
        if case .ready = checkOnDeviceAvailability() { return true }
        return false
    }

    /// Default provider for a brand-new install with no saved preference:
    /// `.onDevice` when Apple Intelligence is available, else `.anthropic`.
    public static func smartDefaultProvider() -> AIProviderType {
        isOnDeviceAvailable() ? .onDevice : .anthropic
    }

    private static func applyAnthropicKeyIfChanged(
        _ key: String,
        router: AIServiceRouter,
        config: BYOKConfiguration
    ) {
        guard key != lastAppliedAnthropicKey else { return }
        lastAppliedAnthropicKey = key
        let endpoint = UserDefaults.standard.string(forKey: config.endpointDefaultsKey) ?? ""
        let model = UserDefaults.standard.string(forKey: config.modelDefaultsKey) ?? ""
        ProviderConfigurator.configureAnthropic(
            router: router,
            apiKey: key,
            endpoint: endpoint.isEmpty ? config.defaultEndpoint : endpoint,
            model: model.isEmpty ? config.defaultModel : model
        )
    }

    // MARK: - On-device check

    private static func checkOnDeviceAvailability() -> ProviderReadiness {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .ready
            case .unavailable(.deviceNotEligible):
                return .onDeviceUnavailable(
                    reason: "This device doesn't support Apple Intelligence. Switch to Claude in Settings and add an API key."
                )
            case .unavailable(.appleIntelligenceNotEnabled):
                return .onDeviceUnavailable(
                    reason: "Apple Intelligence is turned off. Enable it in System Settings, or switch to Claude in Settings."
                )
            case .unavailable(.modelNotReady):
                return .onDeviceUnavailable(
                    reason: "The on-device model is still downloading. Try again in a moment."
                )
            default:
                return .onDeviceUnavailable(
                    reason: "The on-device model isn't available. Switch to Claude in Settings."
                )
            }
        }
        #endif
        return .onDeviceUnavailable(
            reason: "On-device AI requires macOS 26 / iOS 26 with Apple Intelligence. Switch to Claude in Settings and add an API key."
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderReadiness`
Expected: PASS (3 tests). (On CI/macOS < 26 the on-device path returns `.onDeviceUnavailable`;
these tests exercise the `.anthropic` path only.)

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftAIKit/Configuration/ProviderReadiness.swift Tests/SwiftAIKitTests/ProviderReadinessTests.swift
git commit -m "feat: add ProviderReadiness + checker (SecretStore-backed)"
```

---

### Task A5: `ProviderConfigurator` — SecretStore-backed Anthropic configure

Add a convenience that reads the key from a `SecretStore` (endpoint/model still from
UserDefaults), so apps stop passing plaintext keys through UserDefaults.

**Files:**
- Modify: `Sources/SwiftAIKit/Configuration/ProviderConfigurator.swift`
- Test: `Tests/SwiftAIKitTests/ProviderConfiguratorStoreTests.swift`

**Interfaces:**
- Consumes: `SecretStore` (A1), `BYOKConfiguration` (A3), existing `configureAnthropic`.
- Produces: `static func configureAnthropic(router:secretStore:config:session:)`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiftAIKitTests/ProviderConfiguratorStoreTests.swift
import Foundation
import Testing
@testable import SwiftAIKit

@MainActor
@Suite("ProviderConfigurator + SecretStore")
struct ProviderConfiguratorStoreTests {

    @Test("configures anthropic provider from the secret store")
    func configuresFromStore() async {
        let router = AIServiceRouter(defaultProvider: .anthropic, defaultsKey: "test_cfg_1")
        let store = InMemorySecretStore()
        store.set("sk-ant-stored", forKey: BYOKConfiguration.default.apiKeyAccount)

        ProviderConfigurator.configureAnthropic(
            router: router, secretStore: store, config: .default
        )
        router.activeProviderType = .anthropic
        // A configured provider with a non-empty key reports available.
        let available = await router.isProviderAvailable(.anthropic)
        #expect(available)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "ProviderConfigurator + SecretStore"`
Expected: FAIL — ambiguous/undefined overload.

- [ ] **Step 3: Add the implementation**

Append to `ProviderConfigurator` (inside the `enum`, after the existing
`configureAnthropic(router:apiKey:...)`):

```swift
    /// Configure the Anthropic provider, reading the API key from a `SecretStore`
    /// (the secure path) and the endpoint/model overrides from UserDefaults.
    @MainActor
    public static func configureAnthropic(
        router: AIServiceRouter,
        secretStore: SecretStore,
        config: BYOKConfiguration = .default,
        session: URLSession = .shared
    ) {
        let key = secretStore.string(forKey: config.apiKeyAccount) ?? ""
        let endpoint = UserDefaults.standard.string(forKey: config.endpointDefaultsKey) ?? ""
        let model = UserDefaults.standard.string(forKey: config.modelDefaultsKey) ?? ""
        configureAnthropic(
            router: router,
            apiKey: key,
            endpoint: endpoint.isEmpty ? config.defaultEndpoint : endpoint,
            model: model.isEmpty ? config.defaultModel : model,
            session: session
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "ProviderConfigurator + SecretStore"`
Expected: PASS.

- [ ] **Step 5: Run the full core suite + commit**

Run: `swift test`
Expected: All tests pass.

```bash
git add Sources/SwiftAIKit/Configuration/ProviderConfigurator.swift Tests/SwiftAIKitTests/ProviderConfiguratorStoreTests.swift
git commit -m "feat: ProviderConfigurator.configureAnthropic(secretStore:) overload"
```

---

## PHASE B — SwiftAIKitUI target

### Task B1: Add the `SwiftAIKitUI` target to `Package.swift`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwiftAIKitUI/Placeholder.swift` (temporary, so the target compiles)
- Create: `Tests/SwiftAIKitUITests/SmokeTests.swift`

**Interfaces:**
- Produces: a `SwiftAIKitUI` library product depending on `SwiftAIKit`.

- [ ] **Step 1: Edit `Package.swift`**

Replace the `products:` and `targets:` arrays with:

```swift
    products: [
        .library(
            name: "SwiftAIKit",
            targets: ["SwiftAIKit"]
        ),
        .library(
            name: "SwiftAIKitUI",
            targets: ["SwiftAIKitUI"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftAIKit",
            path: "Sources/SwiftAIKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "SwiftAIKitUI",
            dependencies: ["SwiftAIKit"],
            path: "Sources/SwiftAIKitUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SwiftAIKitTests",
            dependencies: ["SwiftAIKit"],
            path: "Tests/SwiftAIKitTests"
        ),
        .testTarget(
            name: "SwiftAIKitUITests",
            dependencies: ["SwiftAIKitUI"],
            path: "Tests/SwiftAIKitUITests"
        ),
    ]
```

- [ ] **Step 2: Add a placeholder source + smoke test so the new targets build**

```swift
// Sources/SwiftAIKitUI/Placeholder.swift
// Temporary anchor so the target compiles before B2 lands. Deleted in B2.
import Foundation
enum SwiftAIKitUIPlaceholder {}
```

```swift
// Tests/SwiftAIKitUITests/SmokeTests.swift
import Testing
@testable import SwiftAIKitUI

@Suite("SwiftAIKitUI smoke")
struct SwiftAIKitUISmokeTests {
    @Test("module builds")
    func builds() {
        #expect(Bool(true))
    }
}
```

- [ ] **Step 3: Build + test to verify both targets resolve**

Run: `swift build && swift test --filter "SwiftAIKitUI smoke"`
Expected: Build succeeds; smoke test passes.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SwiftAIKitUI/Placeholder.swift Tests/SwiftAIKitUITests/SmokeTests.swift
git commit -m "build: add SwiftAIKitUI library + test target"
```

---

### Task B2: `AIProviderSettingsModel` (testable form logic)

Extract the form's logic (provider switch, key persistence, reconfigure, unlock) into an
`@Observable` model so it is unit-testable independent of SwiftUI.

**Files:**
- Create: `Sources/SwiftAIKitUI/AIProviderSettingsModel.swift`
- Delete: `Sources/SwiftAIKitUI/Placeholder.swift`
- Test: `Tests/SwiftAIKitUITests/AIProviderSettingsModelTests.swift`

**Interfaces:**
- Consumes: `AIServiceRouter`, `AIProviderType`, `SecretStore`, `BYOKConfiguration`,
  `ProviderConfigurator` (all from SwiftAIKit).
- Produces: `@MainActor @Observable final class AIProviderSettingsModel` with:
  - `init(router:secretStore:config:)`
  - `var provider: AIProviderType { get set }` (persists to UserDefaults + router)
  - `var endpoint: String { get set }`, `var model: String { get set }` (persist to UserDefaults)
  - `var apiKey: String` (in-memory mirror), `var isKeyUnlocked: Bool`
  - `func loadKeyForReveal()`, `func persistKey()`, `func reconfigure()`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiftAIKitUITests/AIProviderSettingsModelTests.swift
import Foundation
import Testing
@testable import SwiftAIKit
@testable import SwiftAIKitUI

@MainActor
@Suite("AIProviderSettingsModel")
struct AIProviderSettingsModelTests {

    private func makeModel() -> (AIProviderSettingsModel, InMemorySecretStore, AIServiceRouter) {
        let router = AIServiceRouter(defaultProvider: .onDevice, defaultsKey: "ui_test_provider")
        let store = InMemorySecretStore()
        let model = AIProviderSettingsModel(router: router, secretStore: store, config: .default)
        return (model, store, router)
    }

    @Test("persistKey writes the key to the secret store")
    func persistKey() {
        let (model, store, _) = makeModel()
        model.apiKey = "sk-ant-new"
        model.persistKey()
        #expect(store.string(forKey: BYOKConfiguration.default.apiKeyAccount) == "sk-ant-new")
    }

    @Test("setting provider updates the router's active provider")
    func providerSwitch() {
        let (model, _, router) = makeModel()
        model.provider = .anthropic
        #expect(router.activeProviderType == .anthropic)
    }

    @Test("loadKeyForReveal pulls the stored key into apiKey and unlocks")
    func reveal() {
        let (model, store, _) = makeModel()
        store.set("sk-ant-stored", forKey: BYOKConfiguration.default.apiKeyAccount)
        model.loadKeyForReveal()
        #expect(model.apiKey == "sk-ant-stored")
        #expect(model.isKeyUnlocked)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AIProviderSettingsModel`
Expected: FAIL — type not defined.

- [ ] **Step 3: Write the implementation (and delete the placeholder)**

```swift
// Sources/SwiftAIKitUI/AIProviderSettingsModel.swift
import Foundation
import SwiftAIKit

/// Logic for the BYOK provider-settings form, independent of SwiftUI so it can
/// be unit-tested. The view binds to this model.
@MainActor
@Observable
public final class AIProviderSettingsModel {

    private let router: AIServiceRouter
    private let secretStore: SecretStore
    private let config: BYOKConfiguration

    /// In-memory mirror of the key field (only populated after an unlock).
    public var apiKey: String = ""

    /// Whether the key field is revealed (gated behind device auth in the view).
    public var isKeyUnlocked: Bool = false

    /// Guards onChange persistence against re-writing the value we just loaded.
    private var lastPersistedKey: String = ""

    public init(
        router: AIServiceRouter,
        secretStore: SecretStore,
        config: BYOKConfiguration = .default
    ) {
        self.router = router
        self.secretStore = secretStore
        self.config = config
        self.endpoint = UserDefaults.standard.string(forKey: config.endpointDefaultsKey) ?? ""
        self.model = UserDefaults.standard.string(forKey: config.modelDefaultsKey) ?? ""
    }

    /// Active provider, persisted to UserDefaults and pushed to the router.
    public var provider: AIProviderType {
        get { router.activeProviderType }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: config.providerDefaultsKey)
            router.activeProviderType = newValue
        }
    }

    /// Endpoint override (persisted on set).
    public var endpoint: String {
        didSet {
            UserDefaults.standard.set(endpoint, forKey: config.endpointDefaultsKey)
            reconfigure()
        }
    }

    /// Model override (persisted on set).
    public var model: String {
        didSet {
            UserDefaults.standard.set(model, forKey: config.modelDefaultsKey)
            reconfigure()
        }
    }

    /// Load the stored key (fresh read) into `apiKey` and reveal the field.
    public func loadKeyForReveal() {
        let stored = secretStore.refreshedString(forKey: config.apiKeyAccount) ?? ""
        lastPersistedKey = stored
        apiKey = stored
        isKeyUnlocked = true
    }

    /// Persist the current `apiKey` to the secret store (no-op if unchanged).
    public func persistKey() {
        guard apiKey != lastPersistedKey else { return }
        lastPersistedKey = apiKey
        secretStore.set(apiKey, forKey: config.apiKeyAccount)
        reconfigure()
    }

    /// Re-register the Anthropic provider on the router with current values.
    public func reconfigure() {
        ProviderConfigurator.configureAnthropic(
            router: router,
            apiKey: apiKey,
            endpoint: endpoint.isEmpty ? config.defaultEndpoint : endpoint,
            model: model.isEmpty ? config.defaultModel : model
        )
    }
}
```

```bash
rm Sources/SwiftAIKitUI/Placeholder.swift
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AIProviderSettingsModel`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftAIKitUI/AIProviderSettingsModel.swift Tests/SwiftAIKitUITests/AIProviderSettingsModelTests.swift
git rm Sources/SwiftAIKitUI/Placeholder.swift
git commit -m "feat: AIProviderSettingsModel (testable BYOK form logic)"
```

---

### Task B3: `AIProviderSettingsView` (thin SwiftUI view)

The reusable settings form. Thin wrapper over `AIProviderSettingsModel`, with the Touch-ID lock
on the key field. No unit test (SwiftUI view without snapshot infra); verified by `swift build`
and exercised in Phase C.

**Files:**
- Create: `Sources/SwiftAIKitUI/AIProviderSettingsView.swift`

**Interfaces:**
- Consumes: `AIProviderSettingsModel` (B2), `AIServiceRouter`, `AIProviderType`, `SecretStore`,
  `BYOKConfiguration`.
- Produces: `public struct AIProviderSettingsView: View` with
  `init(router:secretStore:config:visibleProviders:)`.

- [ ] **Step 1: Write the implementation**

```swift
// Sources/SwiftAIKitUI/AIProviderSettingsView.swift
import SwiftUI
import LocalAuthentication
import SwiftAIKit

/// Reusable BYOK provider-settings form: provider picker, Touch-ID-gated API key
/// field, and endpoint/model overrides. Drop into an app's Settings scene.
public struct AIProviderSettingsView: View {

    @State private var model: AIProviderSettingsModel
    private let config: BYOKConfiguration
    private let visibleProviders: [AIProviderType]

    /// - Parameters:
    ///   - router: the app's shared `AIServiceRouter`.
    ///   - secretStore: where the API key is stored (e.g. `KeychainSecretStore`).
    ///   - config: key names + defaults.
    ///   - visibleProviders: providers to show in the picker (default on-device + anthropic).
    public init(
        router: AIServiceRouter,
        secretStore: SecretStore,
        config: BYOKConfiguration = .default,
        visibleProviders: [AIProviderType] = [.onDevice, .anthropic]
    ) {
        _model = State(initialValue: AIProviderSettingsModel(
            router: router, secretStore: secretStore, config: config
        ))
        self.config = config
        self.visibleProviders = visibleProviders
    }

    public var body: some View {
        Section {
            Picker("Provider", selection: Binding(
                get: { model.provider },
                set: { model.provider = $0 }
            )) {
                ForEach(visibleProviders) { p in
                    Text(p.displayName).tag(p)
                }
            }
            #if os(macOS)
            .pickerStyle(.radioGroup)
            #endif

            if model.provider == .anthropic {
                if model.isKeyUnlocked {
                    SecureField("API Key", text: Binding(
                        get: { model.apiKey },
                        set: { model.apiKey = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.apiKey) { _, _ in model.persistKey() }
                } else {
                    HStack {
                        Label("API key is locked", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Unlock…") { unlock() }
                    }
                }

                TextField("Endpoint", text: Binding(
                    get: { model.endpoint }, set: { model.endpoint = $0 }
                ), prompt: Text(config.defaultEndpoint))
                .textFieldStyle(.roundedBorder)

                TextField("Model", text: Binding(
                    get: { model.model }, set: { model.model = $0 }
                ), prompt: Text(config.defaultModel))
                .textFieldStyle(.roundedBorder)

                Text("Get an API key at [console.anthropic.com](https://console.anthropic.com)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("AI Provider", systemImage: "brain")
        }
    }

    /// Authenticate as the device owner, then reveal the key field. If no auth
    /// is available, reveal directly rather than locking the user out.
    private func unlock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            model.loadKeyForReveal()
            return
        }
        Task {
            do {
                let ok = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "unlock your Claude API key"
                )
                if ok { model.loadKeyForReveal() }
            } catch {
                // Cancelled — stay locked.
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds (both `SwiftAIKit` and `SwiftAIKitUI`).

- [ ] **Step 3: Run the whole suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 4: Commit + tag a release for consumers**

```bash
git add Sources/SwiftAIKitUI/AIProviderSettingsView.swift
git commit -m "feat: AIProviderSettingsView (reusable BYOK settings form)"
git tag 0.2.0
```

> Push + tag so DiagramDesigner (and CareerPilot) can pin the new version:
> `git push origin main && git push origin 0.2.0`. (Version `0.2.0` assumes the current
> released tag is `0.1.x`; if not, bump to the next minor above the current tag —
> check with `git tag --list | sort -V | tail -1`.)

---

## PHASE C — Migrate DiagramDesigner to consume the shared code

> This phase edits the **DiagramDesigner** repo (`~/Repositories/DiagramDesigner`) and its Xcode
> project. It removes the now-duplicated local files and points the app at SwiftAIKit's shared
> types. Because it touches `project.pbxproj`, prefer doing the add/remove file steps in Xcode.

### Task C1: Bump the SwiftAIKit pin and add the `SwiftAIKitUI` product

**Files:**
- Modify: `DiagramDesigner.xcodeproj` (package pin + product dependency).

- [ ] **Step 1:** In Xcode, open DiagramDesigner → Project → Package Dependencies → select
  `SwiftAIKit` → set the version rule to **Up to Next Minor / Exact `0.2.0`** (the tag from B3).
- [ ] **Step 2:** Target DiagramDesigner → General → Frameworks, Libraries, and Embedded Content
  → **+** → add the **`SwiftAIKitUI`** library product.
- [ ] **Step 3:** Build to confirm resolution.

Run: `xcodebuild -scheme DiagramDesigner -configuration Debug build`
Expected: Build succeeds (still using the local `KeychainStore`/`AIProviderReadiness` for now).

- [ ] **Step 4: Commit**

```bash
cd ~/Repositories/DiagramDesigner
git add -A && git commit -m "build: pin SwiftAIKit 0.2.0 + link SwiftAIKitUI"
```

### Task C2: Replace `KeychainStore` with `KeychainSecretStore`

**Files:**
- Delete: `DiagramDesigner/Services/KeychainStore.swift`
- Modify: `DiagramDesigner/DiagramDesignerApp.swift`, `DiagramDesigner/Views/PreferencesView.swift`,
  `DiagramDesigner/Services/AIProviderReadiness.swift` (callers of `KeychainStore`).

- [ ] **Step 1:** Add a shared store accessor. In `DiagramDesignerApp.swift`, below the
  `UserDefaultsKeys` enum, add:

```swift
import SwiftAIKit

/// App-wide secret store (Keychain), scoped to the app's bundle id.
@MainActor let appSecretStore = KeychainSecretStore(service: "com.blazepascal.DiagramDesigner")
```

- [ ] **Step 2:** Replace every `KeychainStore.` call with `appSecretStore.` in
  `DiagramDesignerApp.swift`, `PreferencesView.swift`, and `AIProviderReadiness.swift`.
  (`KeychainStore.set(...)` → `appSecretStore.set(...)`, `KeychainStore.refreshedString(...)`
  → `appSecretStore.refreshedString(...)`, `KeychainStore.string(...)` →
  `appSecretStore.string(...)`.)
- [ ] **Step 3:** In Xcode, delete `Services/KeychainStore.swift` (Move to Trash — removes the
  pbxproj references).
- [ ] **Step 4:** Build.

Run: `xcodebuild -scheme DiagramDesigner -configuration Debug build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: use SwiftAIKit KeychainSecretStore; delete local KeychainStore"
```

### Task C3: Replace `AIProviderReadiness` with SwiftAIKit's `ProviderReadiness`

**Files:**
- Delete: `DiagramDesigner/Services/AIProviderReadiness.swift`
- Modify: call sites of `AIProviderReadiness`/`AIProviderReadinessChecker` (e.g.
  `DiagramViewModel.swift`, `DiagramDesignerApp.swift`).

- [ ] **Step 1:** Define a `BYOKConfiguration` for the app's historical keys. In
  `DiagramDesignerApp.swift`:

```swift
@MainActor let appBYOKConfig = BYOKConfiguration(
    providerDefaultsKey: UserDefaultsKeys.aiProvider,
    apiKeyAccount: UserDefaultsKeys.anthropicAPIKey,
    endpointDefaultsKey: UserDefaultsKeys.anthropicEndpoint,
    modelDefaultsKey: UserDefaultsKeys.anthropicModel
)
```

- [ ] **Step 2:** Replace `AIProviderReadiness` → `ProviderReadiness` and
  `AIProviderReadinessChecker.check(router:)` → `ProviderReadinessChecker.check(router:
  secretStore: appSecretStore, config: appBYOKConfig)` at all call sites.
  `AIProviderReadinessChecker.smartDefaultProvider()` → `ProviderReadinessChecker.smartDefaultProvider()`.
- [ ] **Step 3:** In Xcode, delete `Services/AIProviderReadiness.swift` (Move to Trash).
- [ ] **Step 4:** Build + smoke-run.

Run: `xcodebuild -scheme DiagramDesigner -configuration Debug build`
Expected: Build succeeds. Launch the app; confirm provider gating still works (no key → prompt
to add one).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: use SwiftAIKit ProviderReadiness; delete local copy"
```

### Task C4: Swap `PreferencesView` AI section for `AIProviderSettingsView`

**Files:**
- Modify: `DiagramDesigner/Views/PreferencesView.swift`

- [ ] **Step 1:** Replace the entire first `Section { … } header: { Label("AI Provider"… ) }`
  block (the provider picker + key/endpoint/model fields, plus the now-unused `unlockAPIKey`,
  `revealAPIKey`, `reconfigureAnthropic`, and the `@AppStorage`/`@State` for key/endpoint/model)
  with a single use of the shared view:

```swift
import SwiftAIKit
import SwiftAIKitUI

struct PreferencesView: View {
    @Environment(AIServiceRouter.self) private var router

    var body: some View {
        Form {
            AIProviderSettingsView(
                router: router,
                secretStore: appSecretStore,
                config: appBYOKConfig
            )

            // … existing Acknowledgements section unchanged …
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 540, maxWidth: 800,
               minHeight: 420, idealHeight: 520, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 2:** Build.

Run: `xcodebuild -scheme DiagramDesigner -configuration Debug build`
Expected: Build succeeds.

- [ ] **Step 3:** Launch the app → Settings (⌘,). Verify: provider picker switches; "Unlock…"
  triggers Touch ID; entering a key persists (relaunch → still present); endpoint/model fields
  save.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "refactor: PreferencesView uses shared AIProviderSettingsView"
```

### Task C5: Update DiagramDesigner docs

**Files:**
- Modify: `DiagramDesigner/CLAUDE.md`

- [ ] **Step 1:** Update the "Adding a New AI Provider" and "Secrets" notes to point at
  SwiftAIKit's `KeychainSecretStore`, `ProviderReadinessChecker`, and `SwiftAIKitUI`'s
  `AIProviderSettingsView` instead of the deleted local files. Remove the "Keychain migration is
  a pre-release item" note (now done upstream).
- [ ] **Step 2: Commit**

```bash
git add DiagramDesigner/CLAUDE.md && git commit -m "docs: point BYOK guidance at SwiftAIKit shared components"
```

---

## Self-Review

**Spec coverage** (PRD §14 dependency + the agreed Option A):
- "core gets `SecretStore`/`KeychainSecretStore`" → Tasks A1, A2. ✓
- "core gets readiness" → Task A4. ✓
- "configurator reads from Keychain" → Tasks A5 (+ used in A4/B2). ✓
- "new `SwiftAIKitUI` target with the settings view" → Tasks B1–B3. ✓
- "DiagramDesigner migrates to consume it / never forks" → Tasks C1–C5. ✓
- "shared `BYOKConfiguration` so keys don't diverge" → Task A3. ✓

**Placeholder scan:** No "TBD/TODO/handle edge cases" — every code step shows complete code. The
only intentionally-untested units are `KeychainSecretStore` (environment-bound; logic mirrors the
A1-tested InMemory store) and `AIProviderSettingsView` (SwiftUI; logic lives in the B2-tested
model) — both noted explicitly.

**Type consistency:** `SecretStore` methods (`string`/`refreshedString`/`set`/`removeValue`) are
identical across A1, A2, B2, A4, A5. `BYOKConfiguration` field names
(`apiKeyAccount`/`endpointDefaultsKey`/`modelDefaultsKey`/`providerDefaultsKey`/`defaultEndpoint`/
`defaultModel`) are used consistently in A3, A4, A5, B2, B3. `ProviderReadinessChecker.check(
router:secretStore:config:)` signature matches between A4's definition and C3's call site.
`ProviderConfigurator.configureAnthropic(router:secretStore:config:session:)` matches between A5
and B2/A4 usage (B2/A4 use the `apiKey:` overload, which already exists).

**Open follow-on (not in this plan):** CareerPilot will consume `KeychainSecretStore` +
`AIProviderSettingsView` directly; that's covered by CareerPilot's own Phase 1 plan, not here.
