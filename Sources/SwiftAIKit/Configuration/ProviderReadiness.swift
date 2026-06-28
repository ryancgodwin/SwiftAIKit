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
            // OpenAI is not surfaced in any v1 picker, and BYOKConfiguration models
            // only the Anthropic key — so OpenAI can never be evaluated as ready
            // here. Return a not-ready state WITHOUT reading any key, so an
            // unrelated Anthropic key can't make OpenAI appear configured.
            return .needsAnthropicKey
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
