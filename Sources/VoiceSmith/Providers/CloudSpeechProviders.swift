import Foundation

/// OpenAI-compatible `/audio/transcriptions` — covers OpenAI Whisper and Groq Whisper,
/// which share a wire format.
struct WhisperAPIProvider: SpeechProvider {
    let displayName: String
    let baseURL: String
    let apiKey: String
    let model: String

    func transcribe(audio: URL, language: String?) async throws -> Transcript {
        let boundary = "voicesmith.\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "\(baseURL)/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields: [String: String] = ["model": model, "response_format": "json"]
        if let language, language != "auto" {
            fields["language"] = String(language.prefix(2))
        }
        request.httpBody = try Self.multipartBody(
            boundary: boundary,
            fields: fields,
            fileURL: audio
        )

        let (data, response) = try await send(request)
        try Self.check(response, data: data, provider: displayName)

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String
        else {
            throw VoiceSmithError.transcriptionFailed(provider: displayName, detail: "unreadable response")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceSmithError.emptyRecording }
        return Transcript(text: trimmed, language: (object["language"] as? String) ?? language ?? "auto")
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: false)
        }
    }

    static func multipartBody(boundary: String, fields: [String: String], fileURL: URL) throws -> Data {
        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        for (key, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        let audio = try Data(contentsOf: fileURL)
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    static func check(_ response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw VoiceSmithError.invalidAPIKey(provider: provider)
        default:
            throw VoiceSmithError.transcriptionFailed(
                provider: provider,
                detail: HTTP.decodeErrorMessage(data)
            )
        }
    }
}

/// Deepgram's prerecorded endpoint takes the raw audio body rather than multipart.
struct DeepgramProvider: SpeechProvider {
    let displayName = "Deepgram"
    let apiKey: String
    let model: String

    func transcribe(audio: URL, language: String?) async throws -> Transcript {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var query = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]
        if let language, language != "auto" {
            query.append(URLQueryItem(name: "language", value: String(language.prefix(2))))
        } else {
            query.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: audio)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: false)
        }
        try WhisperAPIProvider.check(response, data: data, provider: displayName)

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let alternatives = channels.first?["alternatives"] as? [[String: Any]],
              let text = alternatives.first?["transcript"] as? String
        else {
            throw VoiceSmithError.transcriptionFailed(provider: displayName, detail: "unreadable response")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceSmithError.emptyRecording }
        let detected = (results["channels"] as? [[String: Any]])?
            .first?["detected_language"] as? String
        return Transcript(text: trimmed, language: detected ?? language ?? "auto")
    }
}

/// AssemblyAI is a two-step API: upload, then poll the transcript to completion.
struct AssemblyAIProvider: SpeechProvider {
    let displayName = "AssemblyAI"
    let apiKey: String
    let model: String

    func transcribe(audio: URL, language: String?) async throws -> Transcript {
        let uploadURL = try await upload(audio)
        let id = try await requestTranscript(audioURL: uploadURL, language: language)
        return try await poll(id: id)
    }

    private func upload(_ audio: URL) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/upload")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpBody = try Data(contentsOf: audio)

        let (data, response) = try await perform(request)
        try WhisperAPIProvider.check(response, data: data, provider: displayName)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = object["upload_url"] as? String
        else { throw VoiceSmithError.transcriptionFailed(provider: displayName, detail: "upload failed") }
        return url
    }

    private func requestTranscript(audioURL: String, language: String?) async throws -> String {
        var body: [String: Any] = ["audio_url": audioURL, "speech_model": model, "punctuate": true]
        if let language, language != "auto" {
            body["language_code"] = String(language.prefix(2))
        } else {
            body["language_detection"] = true
        }

        var request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/transcript")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await perform(request)
        try WhisperAPIProvider.check(response, data: data, provider: displayName)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String
        else { throw VoiceSmithError.transcriptionFailed(provider: displayName, detail: "no transcript id") }
        return id
    }

    private func poll(id: String) async throws -> Transcript {
        var request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/transcript/\(id)")!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        // ~2 minutes of polling; a dictation-length clip finishes well inside that.
        for _ in 0..<120 {
            let (data, response) = try await perform(request)
            try WhisperAPIProvider.check(response, data: data, provider: displayName)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = object["status"] as? String
            else { throw VoiceSmithError.transcriptionFailed(provider: displayName, detail: "unreadable response") }

            switch status {
            case "completed":
                let text = (object["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw VoiceSmithError.emptyRecording }
                return Transcript(text: text, language: (object["language_code"] as? String) ?? "auto")
            case "error":
                throw VoiceSmithError.transcriptionFailed(
                    provider: displayName,
                    detail: (object["error"] as? String) ?? "transcription failed"
                )
            default:
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw VoiceSmithError.transcriptionFailed(provider: displayName, detail: "timed out waiting for the transcript")
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await HTTP.session.data(for: request)
        } catch {
            throw HTTP.classify(error, provider: displayName, isLocal: false)
        }
    }
}
