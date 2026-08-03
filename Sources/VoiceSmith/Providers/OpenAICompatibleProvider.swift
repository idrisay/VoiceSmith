import Foundation

/// One implementation for every `/chat/completions` backend: OpenAI, Gemini's
/// compatibility endpoint, OpenRouter, Groq, DeepSeek, Mistral, and LM Studio.
struct OpenAICompatibleProvider: TextProvider {
    let displayName: String
    let baseURL: String
    let apiKey: String?
    let model: String
    let isLocal: Bool

    func improve(_ text: String, mode: ImprovementMode, language: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Prompts.system(for: mode, language: language)],
                ["role": "user", "content": text],
            ],
            "temperature": 0.2,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: isLocal)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401, 403:
                throw VoiceSmithError.invalidAPIKey(provider: displayName)
            case 404 where isLocal:
                throw VoiceSmithError.localModelUnavailable(
                    provider: displayName,
                    detail: "the server is running but has no model named \(model)"
                )
            default:
                throw VoiceSmithError.improvementFailed(
                    provider: displayName,
                    detail: HTTP.decodeErrorMessage(data)
                )
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "unreadable response")
        }

        let improved = Self.stripReasoning(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !improved.isEmpty else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "the model returned nothing")
        }
        return improved
    }

    /// Reasoning models (DeepSeek R1, several Ollama builds) prepend a `<think>`
    /// block to the message body. The user wants their text, not the reasoning.
    static func stripReasoning(_ text: String) -> String {
        guard let end = text.range(of: "</think>") else { return text }
        return String(text[end.upperBound...])
    }
}

/// Ollama's native `/api/chat`. Kept separate from the OpenAI shape so model
/// discovery via `/api/tags` can live alongside it.
struct OllamaProvider: TextProvider {
    let displayName = "Ollama"
    let baseURL: String
    let model: String

    func improve(_ text: String, mode: ImprovementMode, language: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": Prompts.system(for: mode, language: language)],
                ["role": "user", "content": text],
            ],
            "options": ["temperature": 0.2],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: true)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let detail = HTTP.decodeErrorMessage(data)
            if http.statusCode == 404 {
                throw VoiceSmithError.localModelUnavailable(
                    provider: displayName,
                    detail: "\(model) isn't installed. Run `ollama pull \(model)`."
                )
            }
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: detail)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "unreadable response")
        }

        let improved = OpenAICompatibleProvider.stripReasoning(content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !improved.isEmpty else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "the model returned nothing")
        }
        return improved
    }

    /// Lists locally installed models so Settings can offer them instead of
    /// making the user type a model name.
    static func installedModels(baseURL: String) async -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        guard let (data, _) = try? await HTTP.session.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }
}
