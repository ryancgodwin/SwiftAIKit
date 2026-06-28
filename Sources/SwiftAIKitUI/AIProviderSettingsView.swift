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
