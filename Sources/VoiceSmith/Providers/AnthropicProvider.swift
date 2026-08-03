import Foundation

/// Anthropic Messages API over raw HTTP — there is no official Swift SDK, so this
/// speaks the wire format directly.
struct AnthropicProvider: TextProvider {
    let displayName = "Anthropic"
    let apiKey: String
    let model: String

    private static let apiVersion = "2023-06-01"

    func improve(_ text: String, mode: ImprovementMode, language: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Opt into server-side fallbacks: if safety classifiers decline a dictation,
        // the API re-runs it on the recommended fallback model in the same call
        // rather than handing us a refusal.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "system": Prompts.system(for: mode, language: language),
            "messages": [["role": "user", "content": text]],
            "fallbacks": "default",
        ]

        // Cleanup is a mechanical rewrite, and latency is the whole product here,
        // so thinking is off. Disabling it is only permitted at effort `high` or
        // below, which is why effort is pinned rather than left at its default.
        if Self.isOpusFamily(model) {
            body["thinking"] = ["type": "disabled"]
            body["output_config"] = ["effort": "low"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: false)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401, 403:
                throw VoiceSmithError.invalidAPIKey(provider: displayName)
            default:
                throw VoiceSmithError.improvementFailed(
                    provider: displayName,
                    detail: HTTP.decodeErrorMessage(data)
                )
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "unreadable response")
        }

        // A refusal is a 200 with an empty or partial content array — check the
        // stop reason before touching `content`.
        if object["stop_reason"] as? String == "refusal" {
            throw VoiceSmithError.refused(provider: displayName)
        }

        guard let content = object["content"] as? [[String: Any]] else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "no content in response")
        }

        let improved = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !improved.isEmpty else {
            throw VoiceSmithError.improvementFailed(provider: displayName, detail: "the model returned nothing")
        }
        return improved
    }

    /// `thinking` and `output_config` are only valid on the current Claude models;
    /// older ones reject them, so send them only when the model id looks current.
    private static func isOpusFamily(_ model: String) -> Bool {
        model.hasPrefix("claude-opus-5")
            || model.hasPrefix("claude-opus-4-")
            || model.hasPrefix("claude-sonnet-5")
            || model.hasPrefix("claude-fable-5")
    }
}
