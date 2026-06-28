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

    /// Re-register the Anthropic provider on the router using the stored key and
    /// the current endpoint/model overrides. The key is read from the secret
    /// store (not the in-memory `apiKey` mirror, which is empty while the field
    /// is locked) so that editing endpoint/model never clobbers a stored key
    /// with an empty value.
    public func reconfigure() {
        ProviderConfigurator.configureAnthropic(
            router: router,
            secretStore: secretStore,
            config: config
        )
    }
}
