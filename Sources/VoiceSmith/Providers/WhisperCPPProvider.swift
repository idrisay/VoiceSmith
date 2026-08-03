import AVFoundation
import Foundation

/// Local transcription by shelling out to a whisper.cpp binary. Fully offline.
/// whisper.cpp only reads 16 kHz mono WAV, so the recording is converted first.
struct WhisperCPPProvider: SpeechProvider {
    let displayName = "Whisper.cpp"
    let binaryPath: String
    let modelPath: String

    /// Common install locations, checked in order when the user hasn't set a path.
    static let candidateBinaries = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cpp",
        "/opt/homebrew/bin/main",
    ]

    static func discoverBinary() -> String? {
        candidateBinaries.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func transcribe(audio: URL, language: String?) async throws -> Transcript {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw VoiceSmithError.localModelUnavailable(
                provider: displayName,
                detail: "no whisper.cpp binary at \(binaryPath). Install it with `brew install whisper-cpp`, then set the path in Settings › Providers."
            )
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw VoiceSmithError.localModelUnavailable(
                provider: displayName,
                detail: "no model file at \(modelPath). Download a ggml model and set its path in Settings › Providers."
            )
        }

        let wav = try await Self.convertToWAV(audio)
        defer { try? FileManager.default.removeItem(at: wav) }

        var arguments = [
            "-m", modelPath,
            "-f", wav.path,
            "--no-timestamps",
            "--output-txt", "false",
        ]
        if let language, language != "auto" {
            arguments.append(contentsOf: ["-l", String(language.prefix(2))])
        } else {
            arguments.append(contentsOf: ["-l", "auto"])
        }

        let output = try Self.run(binaryPath, arguments: arguments, provider: displayName)
        let text = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // whisper.cpp writes progress and timing lines to stdout alongside the text.
            .filter { !$0.isEmpty && !$0.hasPrefix("[") && !$0.hasPrefix("whisper_") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw VoiceSmithError.emptyRecording }
        return Transcript(text: text, language: language ?? "auto")
    }

    // MARK: - Helpers

    private static func run(_ path: String, arguments: [String], provider: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw VoiceSmithError.localModelUnavailable(provider: provider, detail: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw VoiceSmithError.transcriptionFailed(
                provider: provider,
                detail: "whisper.cpp exited with status \(process.terminationStatus)"
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// whisper.cpp requires 16 kHz mono 16-bit PCM.
    static func convertToWAV(_ source: URL) async throws -> URL {
        let output = Storage.audioDirectory.appendingPathComponent("\(UUID().uuidString).wav")

        let asset = AVURLAsset(url: source)
        guard let reader = try? AVAssetReader(asset: asset),
              let track = try await asset.loadTracks(withMediaType: .audio).first
        else {
            throw VoiceSmithError.transcriptionFailed(provider: "Whisper.cpp", detail: "couldn't read the recording")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        while let buffer = readerOutput.copyNextSampleBuffer() {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            writerInput.append(buffer)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw VoiceSmithError.transcriptionFailed(
                provider: "Whisper.cpp",
                detail: writer.error?.localizedDescription ?? "audio conversion failed"
            )
        }
        return output
    }
}
