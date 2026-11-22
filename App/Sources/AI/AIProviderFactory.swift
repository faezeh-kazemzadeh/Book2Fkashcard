import Foundation
import B2FCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Builds the configured `AIProvider`. The UI only ever sees `any AIProvider`,
/// so switching between OpenAI, Azure OpenAI, the backend proxy, Apple's
/// on-device model or a future local model requires no UI changes.
struct AIProviderFactory {
    let settings: AppSettings
    let credentials: APICredentialStore

    func makeProvider() -> (any AIProvider)? {
        if ProcessInfo.processInfo.arguments.contains("-UITestMockAI") { return UITestAIProvider.make() }
        switch settings.aiProvider {
        case .openAI:
            guard let key = credentials.value(.openAIKey) else { return nil }
            return ChatCompletionsProvider(endpoint: .openAI(apiKey: key, model: settings.openAIModel))
        case .azureOpenAI:
            guard let key = credentials.value(.azureKey), let endpoint = URL(string: settings.azureEndpoint),
                  endpoint.scheme == "https", !settings.azureDeployment.isEmpty else { return nil }
            return ChatCompletionsProvider(endpoint: .azure(endpoint: endpoint, deployment: settings.azureDeployment,
                                                            apiVersion: settings.azureAPIVersion, apiKey: key))
        case .proxy:
            guard let base = URL(string: settings.proxyBaseURL), base.scheme == "https",
                  let token = credentials.value(.proxyToken) else { return nil }
            return ChatCompletionsProvider(endpoint: .proxy(baseURL: base, model: settings.openAIModel, token: token))
        case .appleOnDevice:
            return AppleOnDeviceProvider.makeIfAvailable()
        case .localModel:
            return nil
        }
    }

    var isConfigured: Bool { makeProvider() != nil }
}

/// Apple Intelligence on-device model (iOS 26+, Foundation Models framework).
/// Runs privately and offline. The ~4k-token context suits explanations and
/// small lessons; the generator's chunking keeps requests within it.
struct AppleOnDeviceProvider: AIProvider {
    let identifier = "apple-on-device"
    let capabilities: AICapabilities = [.onDevice]

    static func makeIfAvailable() -> (any AIProvider)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return AppleOnDeviceProvider()
        }
        #endif
        return nil
    }

    static var isAvailable: Bool { makeIfAvailable() != nil }

    func complete(_ request: AIRequest) async throws -> AIResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            var instructions = request.system
            if let schema = request.schema, let data = try? JSONEncoder().encode(schema.schema),
               let json = String(data: data, encoding: .utf8) {
                // The on-device model has no JSON-schema mode for dynamic schemas;
                // instruct it explicitly and rely on tolerant decoding.
                instructions += "\n\nRespond ONLY with JSON matching this JSON Schema, no prose:\n\(json)"
            }
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: request.user)
                return AIResponse(text: response.content)
            } catch {
                throw AIError.unavailable("Apple Intelligence could not complete the request: \(error.localizedDescription)")
            }
        }
        #endif
        throw AIError.unavailable("Apple Intelligence is not available on this device.")
    }
}

/// Deterministic provider injected during UI tests (`-UITestMockAI`).
enum UITestAIProvider {
    static func make() -> any AIProvider {
        MockAIProvider { request in
            if request.schema?.name == "lesson_flashcards" {
                return #"{"vocabulary":[{"term":"resilient","translation":"مقاوم","definition":"able to recover quickly","ipa":"rɪˈzɪliənt","pronunciation":"ri-ZIL-ee-uhnt","partOfSpeech":"adjective","example":"Children are resilient.","exampleTranslation":"کودکان مقاوم هستند.","synonyms":["tough"],"antonyms":["fragile"],"priority":"essential","confidence":0.95}],"grammar":[],"reading":[],"speaking":[]}"#
            }
            if request.schema?.name == "lesson_outline" { return #"{"lessons":[]}"# }
            return "A short explanation."
        }
    }
}
