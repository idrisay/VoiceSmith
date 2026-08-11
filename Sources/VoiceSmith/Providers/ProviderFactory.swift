import Foundation

/// Turns settings into provider instances. The only place in the app that knows
/// which concrete type backs which menu entry.
enum ProviderFactory {
    static func speech(_ settings: AppSettings) throws -> SpeechProvider {
        let kind = settings.speechProvider
        let model = settings.speechModel.isEmpty ? kind.defaultModel : settings.speechModel

        func key() throws -> String {
            guard let account = kind.keychainAccount, let value = Keychain.get(account), !value.isEmpty else {
                throw VoiceSmithError.missingAPIKey(provider: kind.displayName)
            }
            return value
        }

        switch kind {
        case .appleSpeech:
            return AppleSpeechProvider()
        case .whisperCPP:
            // Emptied rather than nil: clearing the field in Settings persists
            // "", which `??` would happily accept as a path and turn into "no
            // whisper.cpp binary at ". Clearing it should hand the search back
            // to auto-discovery, which is what it looks like it does.
            let configuredBinary = UserDefaults.standard.string(forKey: "whisperBinaryPath")
            let binary = configuredBinary?.isEmpty == false
                ? configuredBinary!
                : WhisperCPPProvider.discoverBinary() ?? "/opt/homebrew/bin/whisper-cli"
            let modelPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
            return WhisperCPPProvider(binaryPath: binary, modelPath: modelPath)
        case .openAIWhisper:
            return WhisperAPIProvider(
                displayName: kind.displayName,
                baseURL: "https://api.openai.com/v1",
                apiKey: try key(),
                model: model
            )
        case .groqWhisper:
            return WhisperAPIProvider(
                displayName: kind.displayName,
                baseURL: "https://api.groq.com/openai/v1",
                apiKey: try key(),
                model: model
            )
        case .deepgram:
            return DeepgramProvider(apiKey: try key(), model: model)
        case .assemblyAI:
            return AssemblyAIProvider(apiKey: try key(), model: model)
        }
    }

    static func text(_ settings: AppSettings) throws -> TextProvider {
        let kind = settings.textProvider
        let model = settings.textModel.isEmpty ? kind.defaultModel : settings.textModel

        func key() throws -> String {
            guard let account = kind.keychainAccount, let value = Keychain.get(account), !value.isEmpty else {
                throw VoiceSmithError.missingAPIKey(provider: kind.displayName)
            }
            return value
        }

        switch kind {
        case .anthropic:
            return AnthropicProvider(apiKey: try key(), model: model)
        case .ollama:
            return OllamaProvider(baseURL: kind.defaultBaseURL, model: model)
        case .lmStudio:
            return OpenAICompatibleProvider(
                displayName: kind.displayName,
                baseURL: kind.defaultBaseURL,
                apiKey: nil,
                model: model,
                isLocal: true
            )
        case .openAI, .googleGemini, .openRouter, .groq, .deepSeek, .mistral:
            return OpenAICompatibleProvider(
                displayName: kind.displayName,
                baseURL: kind.defaultBaseURL,
                apiKey: try key(),
                model: model,
                isLocal: false
            )
        }
    }
}
