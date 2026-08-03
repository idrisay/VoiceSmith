import AVFoundation
import AppKit
import Combine
import Foundation

/// The pipeline: invoke → record → transcribe → improve → deliver → review.
@MainActor
final class AppController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case improving
        case done(noteID: UUID)
        case failed(VoiceSmithError)

        var isBusy: Bool {
            switch self {
            case .recording, .transcribing, .improving: return true
            default: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusDetail: String = ""
    /// Audio kept aside after a failure so the user can retry without re-dictating.
    @Published private(set) var pendingAudio: URL?

    let recorder = AudioRecorder()
    let settings: AppSettings
    let store: NoteStore

    private var targetApplication: NSRunningApplication?
    private var work: Task<Void, Never>?
    private var windowPresenter: (() -> Void)?
    private var windowDismisser: (() -> Void)?

    init(settings: AppSettings, store: NoteStore) {
        self.settings = settings
        self.store = store

        recorder.onInterruption = { [weak self] error, url in
            Task { @MainActor in self?.handleInterruption(error, audio: url) }
        }
    }

    func attachWindow(present: @escaping () -> Void, dismiss: @escaping () -> Void) {
        windowPresenter = present
        windowDismisser = dismiss
    }

    // MARK: - Invoke

    /// The global shortcut and the menu bar item both land here. Pressing again
    /// while recording stops — that's the one-key round trip the product is built on.
    func toggle() {
        switch phase {
        case .recording:
            stopAndProcess()
        case .idle, .done, .failed:
            beginRecording()
        case .transcribing, .improving:
            break // Already working; ignore.
        }
    }

    func beginRecording() {
        // Remember where the text should end up before we steal focus.
        targetApplication = NSWorkspace.shared.frontmostApplication

        Task { @MainActor in
            guard await ensureMicrophoneAccess() else {
                present(.microphonePermissionDenied)
                return
            }

            do {
                try recorder.start(maxSeconds: TimeInterval(settings.maxRecordingSeconds))
                phase = .recording
                statusDetail = ""
                pendingAudio = nil
                windowPresenter?()
            } catch let error as VoiceSmithError {
                present(error)
            } catch {
                present(.recordingFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Controls

    func pause() { recorder.pause() }
    func resume() { recorder.resume() }

    /// Escape: throw the audio away and get out of the way.
    func cancel() {
        work?.cancel()
        recorder.cancel()
        phase = .idle
        statusDetail = ""
        pendingAudio = nil
        windowDismisser?()
    }

    func stopAndProcess() {
        guard phase == .recording else { return }
        let duration = recorder.duration
        guard let audio = recorder.stop() else {
            // Nothing worth sending to a provider — don't spend a request on silence.
            present(.emptyRecording)
            return
        }
        process(audio: audio, duration: duration)
    }

    /// Retry after a failure, reusing the audio we held back.
    func retryPending() {
        guard let audio = pendingAudio else { return }
        process(audio: audio, duration: durationOf(audio))
    }

    func discardPending() {
        if let audio = pendingAudio {
            try? FileManager.default.removeItem(at: audio)
        }
        pendingAudio = nil
        phase = .idle
        windowDismisser?()
    }

    // MARK: - Pipeline

    private func process(audio: URL, duration: TimeInterval) {
        work?.cancel()
        work = Task { @MainActor in
            do {
                // 1. Transcribe.
                phase = .transcribing
                statusDetail = settings.speechProvider.displayName
                let speech = try ProviderFactory.speech(settings)
                let transcript = try await speech.transcribe(
                    audio: audio,
                    language: settings.language == "auto" ? nil : settings.language
                )
                try Task.checkCancellation()

                // 2. Improve. A failure here is non-fatal: the raw transcript is
                // still worth delivering, so we report and continue.
                var improved: String?
                var textProviderName: String?
                var textModelName: String?
                var improvementError: VoiceSmithError?

                if settings.improveAutomatically {
                    phase = .improving
                    statusDetail = settings.textProvider.displayName
                    do {
                        let text = try ProviderFactory.text(settings)
                        improved = try await text.improve(
                            transcript.text,
                            mode: settings.activeMode,
                            language: settings.language
                        )
                        textProviderName = settings.textProvider.displayName
                        textModelName = settings.textModel
                    } catch let error as VoiceSmithError {
                        improvementError = error
                    }
                }
                try Task.checkCancellation()

                // 3. Persist.
                let keepAudio = settings.audioRetention != .deleteAfterTranscription
                let note = VoiceNote(
                    duration: duration,
                    audioPath: keepAudio ? audio.path : nil,
                    rawTranscript: transcript.text,
                    improvedText: improved,
                    language: transcript.language,
                    mode: settings.activeMode.name,
                    speechProvider: settings.speechProvider.displayName,
                    speechModel: settings.speechModel,
                    textProvider: textProviderName,
                    textModel: textModelName
                )
                store.insert(note)
                if !keepAudio {
                    try? FileManager.default.removeItem(at: audio)
                }

                // 4. Deliver.
                deliver(note.displayText)

                pendingAudio = nil
                phase = .done(noteID: note.id)

                if let improvementError {
                    // Delivered the raw transcript — say so rather than pretending
                    // the improvement step succeeded.
                    statusDetail = improvementError.errorDescription ?? "Improvement failed"
                    present(improvementError, keepingAudio: nil)
                } else {
                    statusDetail = ""
                    windowDismisser?()
                }
            } catch is CancellationError {
                phase = .idle
                windowDismisser?()
            } catch let error as VoiceSmithError {
                // Keep the audio: the user shouldn't have to say it all again.
                present(error, keepingAudio: error == .emptyRecording ? nil : audio)
            } catch {
                present(
                    .transcriptionFailed(
                        provider: settings.speechProvider.displayName,
                        detail: error.localizedDescription
                    ),
                    keepingAudio: audio
                )
            }
        }
    }

    private func deliver(_ text: String) {
        if settings.copyToClipboard {
            Delivery.copyToClipboard(text)
        }
        if settings.autoPaste {
            do {
                try Delivery.paste(into: targetApplication)
            } catch let error as VoiceSmithError {
                // Clipboard still worked — degrade rather than fail.
                statusDetail = error.errorDescription ?? ""
                if settings.showNotification {
                    Delivery.notify(
                        title: "Copied, but not pasted",
                        body: error.recoverySuggestion ?? ""
                    )
                }
                return
            } catch {}
        }
        if settings.showNotification {
            let preview = text.count > 80 ? String(text.prefix(80)) + "…" : text
            Delivery.notify(title: "VoiceSmith", body: preview)
        }
    }

    // MARK: - Re-run

    /// Re-improve an existing note with the current mode and model.
    func reimprove(_ note: VoiceNote, mode: ImprovementMode) {
        Task { @MainActor in
            do {
                let provider = try ProviderFactory.text(settings)
                let improved = try await provider.improve(
                    note.rawTranscript,
                    mode: mode,
                    language: settings.language
                )
                note.improvedText = improved
                note.mode = mode.name
                note.textProvider = settings.textProvider.displayName
                note.textModel = settings.textModel
                store.touch(note)
            } catch let error as VoiceSmithError {
                present(error, keepingAudio: nil)
            } catch {}
        }
    }

    // MARK: - Errors

    private func handleInterruption(_ error: VoiceSmithError, audio: URL?) {
        guard phase == .recording else { return }
        // Device disconnect or the length cap: keep what we captured and offer it.
        present(error, keepingAudio: audio)
    }

    private func present(_ error: VoiceSmithError, keepingAudio audio: URL? = nil) {
        pendingAudio = audio
        phase = .failed(error)
        windowPresenter?()
        if settings.showNotification {
            Delivery.notify(
                title: error.errorDescription ?? "VoiceSmith",
                body: error.recoverySuggestion ?? ""
            )
        }
    }

    func dismissError() {
        guard case .failed = phase else { return }
        phase = .idle
        windowDismisser?()
    }

    // MARK: - Permissions

    private func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func durationOf(_ url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
    }
}
