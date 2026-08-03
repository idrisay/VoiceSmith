import AVFoundation
import Foundation

/// Wraps `AVAudioRecorder` with the metering, pause/resume, and failure handling
/// the recording window needs. All callbacks land on the main queue.
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    /// Rolling window of normalised levels (0…1), newest last. Drives the waveform.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 48)
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPaused = false

    /// Fired when the recorder stops on its own — device disconnect, encoding
    /// failure, or the maximum-length cap. The URL is non-nil when audio survived.
    var onInterruption: ((VoiceSmithError, URL?) -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var deviceObserver: NSObjectProtocol?
    private var maxSeconds: TimeInterval = 600
    private(set) var fileURL: URL?

    /// Refuse to start rather than lose audio mid-capture.
    private static let minimumFreeBytes: Int64 = 200 * 1024 * 1024

    // MARK: - Lifecycle

    func start(maxSeconds: TimeInterval) throws {
        self.maxSeconds = maxSeconds

        try Self.checkDiskSpace()
        guard Self.hasInputDevice() else { throw VoiceSmithError.noInputDevice }

        let url = Storage.newAudioURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw VoiceSmithError.recordingFailed("the audio engine refused to start")
            }
            self.recorder = recorder
            self.fileURL = url
        } catch let error as VoiceSmithError {
            throw error
        } catch {
            throw VoiceSmithError.recordingFailed(error.localizedDescription)
        }

        duration = 0
        isPaused = false
        levels = Array(repeating: 0, count: 48)
        startTimer()
        observeDeviceChanges()
    }

    func pause() {
        guard let recorder, recorder.isRecording else { return }
        recorder.pause()
        isPaused = true
    }

    func resume() {
        guard let recorder, isPaused else { return }
        guard recorder.record() else {
            finish(with: .inputDeviceDisconnected)
            return
        }
        isPaused = false
    }

    /// Stops and returns the finished file. Returns nil if nothing was captured.
    @discardableResult
    func stop() -> URL? {
        teardown()
        guard let url = fileURL else { return nil }
        // A file with no meaningful audio is not worth sending to a provider.
        guard duration >= 0.4, Storage.fileSize(url) > 2_048 else {
            try? FileManager.default.removeItem(at: url)
            fileURL = nil
            return nil
        }
        return url
    }

    /// Stops and discards the audio outright.
    func cancel() {
        teardown()
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
        duration = 0
    }

    // MARK: - Internals

    private func teardown() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isPaused = false
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
            deviceObserver = nil
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            guard !self.isPaused else { return }

            recorder.updateMeters()
            self.duration = recorder.currentTime
            self.appendLevel(from: recorder.averagePower(forChannel: 0))

            if self.duration >= self.maxSeconds {
                self.finish(with: .recordingFailed("reached the \(Int(self.maxSeconds / 60))-minute maximum length"))
            }
        }
    }

    /// dBFS is roughly -60…0; map it onto a curve that looks alive at speech level.
    private func appendLevel(from decibels: Float) {
        let clamped = max(-60, min(0, decibels))
        let normalised = pow(CGFloat((clamped + 60) / 60), 1.8)
        levels.removeFirst()
        levels.append(normalised)
    }

    private func finish(with error: VoiceSmithError) {
        let url = stop()
        onInterruption?(error, url)
    }

    private func observeDeviceChanges() {
        // If the default input goes away mid-recording, keep what we have.
        deviceObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.recorder != nil else { return }
            guard !Self.hasInputDevice() else { return }
            self.finish(with: .inputDeviceDisconnected)
        }
    }

    private static func hasInputDevice() -> Bool {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return !session.devices.isEmpty
    }

    private static func checkDiskSpace() throws {
        let values = try? Storage.audioDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        if let available = values?.volumeAvailableCapacityForImportantUsage,
           available < minimumFreeBytes {
            throw VoiceSmithError.diskFull
        }
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        finish(with: .recordingFailed(error?.localizedDescription ?? "audio encoding failed"))
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag else { return }
        finish(with: .recordingFailed("the recording ended unexpectedly"))
    }
}
