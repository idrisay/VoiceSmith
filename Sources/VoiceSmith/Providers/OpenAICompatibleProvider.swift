import Foundation

/// One implementation for every `/chat/completions` backend: OpenAI, Gemini's
/// compatibility endpoint, OpenRouter, Groq, DeepSeek, Mistral, and LM Studio.
struct OpenAICompatibleProvider: TextProvider {
    let displayName: String
    let baseURL: String
    let apiKey: String?
    let model: String
    let isLocal: Bool

    func complete(system: String, user: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.2,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: isLocal, stage: .improvement)
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
              let choice = choices.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "unreadable response")
        }

        // A reply that hit the output limit parses perfectly well and is missing
        // its ending. Delivering it would silently truncate the user's own words.
        if choice["finish_reason"] as? String == "length" {
            throw VoiceSmithError.improvementFailed(
                provider: displayName,
                detail: "the reply was cut off at the model's output limit"
            )
        }

        let improved = Self.stripReasoning(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !improved.isEmpty else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "the model returned nothing")
        }
        return improved
    }

    /// Tag names reasoning models wrap their thinking in. `think` is DeepSeek
    /// R1's and the most common; the others turn up on various Ollama builds.
    private static let reasoningTags = ["think", "thinking", "reasoning", "thought"]

    /// Reasoning models (DeepSeek R1, several Ollama builds) prepend a `<think>`
    /// block to the message body. The user wants their text, not the reasoning.
    ///
    /// A reply that opens a block and never closes it was cut off mid-thought —
    /// a token limit, a dropped connection, a cancelled request. There is no
    /// answer in it, only reasoning, so it returns nothing and the caller reports
    /// a failure. Handing the raw thinking back as "the improved text" would
    /// paste the model's monologue into whatever the user was writing.
    static func stripReasoning(_ text: String) -> String {
        for tag in reasoningTags {
            if let end = text.range(of: "</\(tag)>", options: [.caseInsensitive]) {
                return String(text[end.upperBound...])
            }
        }

        let leading = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for tag in reasoningTags where leading.hasPrefix("<\(tag)>") {
            return ""
        }

        return text
    }
}

/// Ollama's native `/api/chat`. Kept separate from the OpenAI shape so model
/// discovery via `/api/tags` can live alongside it.
struct OllamaProvider: TextProvider {
    let displayName = "Ollama"
    let baseURL: String
    let model: String

    func complete(system: String, user: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "options": ["temperature": 0.2],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: true, stage: .improvement)
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

        // Ollama's spelling of the same thing: the reply ran out of tokens.
        if object["done_reason"] as? String == "length" {
            throw VoiceSmithError.improvementFailed(
                provider: displayName,
                detail: "the reply was cut off at the model's output limit"
            )
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
