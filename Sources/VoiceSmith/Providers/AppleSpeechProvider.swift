import Foundation
import Speech

/// On-device transcription via the Speech framework. No key, no network, no cost —
/// which is why it's the default.
struct AppleSpeechProvider: SpeechProvider {
    let displayName = "Apple Speech"

    func transcribe(audio: URL, language: String?) async throws -> Transcript {
        let status = await Self.requestAuthorization()
        guard status == .authorized else { throw VoiceSmithError.speechPermissionDenied }

        let locale: Locale = {
            if let language, language != "auto" { return Locale(identifier: language) }
            return Locale.current
        }()

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceSmithError.transcriptionFailed(
                provider: displayName,
                detail: "no recogniser is available for \(locale.identifier)"
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.shouldReportPartialResults = false
        // Keep audio on the machine even when the network path is available.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = true

        let text: String = try await withCheckedThrowingContinuation { continuation in
            // SFSpeechRecognizer can call back more than once; guard against
            // resuming the continuation twice.
            let resumed = ResumeGuard()
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard resumed.claim() else { return }
                    continuation.resume(throwing: VoiceSmithError.transcriptionFailed(
                        provider: "Apple Speech",
                        detail: error.localizedDescription
                    ))
                    return
                }
                guard let result, result.isFinal else { return }
                guard resumed.claim() else { return }
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceSmithError.emptyRecording }
        return Transcript(text: trimmed, language: locale.identifier)
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}

/// Tiny thread-safe latch so a multi-call delegate can't resume a continuation twice.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}
