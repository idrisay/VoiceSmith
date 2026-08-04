import SwiftUI

/// The floating popup. Deliberately small: a mic, a live sound meter, a timer,
/// and a stop button. Everything else — provider names, mode, destination — is
/// in the menu bar and Settings, not in the user's face mid-sentence.
///
/// Once recording stops the pipeline runs on its own: transcribe → improve →
/// insert into the field that had focus. The popup only reports progress.
struct RecordingView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            switch controller.phase {
            case .failed(let error):
                ErrorPill(controller: controller, error: error)
            case .recording:
                recordingPill
            default:
                workingPill
            }
        }
        .fixedSize()
    }

    // MARK: - Recording

    private var recordingPill: some View {
        HStack(spacing: 11) {
            MicIndicator(level: recorder.levels.last ?? 0, isPaused: recorder.isPaused)

            SoundBars(levels: recorder.levels, isPaused: recorder.isPaused)
                .frame(width: 96, height: 26)

            Text(timeString(recorder.duration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Divider().frame(height: 22)

            // Pause is secondary; stop is the one the user reaches for.
            IconButton(
                symbol: recorder.isPaused ? "play.fill" : "pause.fill",
                help: recorder.isPaused ? "Resume" : "Pause"
            ) {
                recorder.isPaused ? controller.resume() : controller.pause()
            }

            IconButton(symbol: "stop.fill", help: "Stop and transcribe", tint: .accentColor) {
                controller.stopAndProcess()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(PillBackground())
    }

    // MARK: - Working

    private var workingPill: some View {
        HStack(spacing: 11) {
            ProgressView().controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text(phaseLabel)
                    .font(.system(size: 12, weight: .medium))
                if !controller.statusDetail.isEmpty {
                    Text(controller.statusDetail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider().frame(height: 22)

            IconButton(symbol: "xmark", help: "Cancel") { controller.cancel() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minWidth: 200, alignment: .leading)
        .background(PillBackground())
    }

    private var phaseLabel: String {
        switch controller.phase {
        case .transcribing: return "Transcribing…"
        case .improving: return "Improving…"
        case .done: return "Inserted"
        default: return "Working…"
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Mic indicator

/// A mic glyph inside a ring that breathes with the incoming level, so the user
/// can see the app is hearing them without reading anything.
private struct MicIndicator: View {
    let level: CGFloat
    let isPaused: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isPaused ? Color.orange.opacity(0.18) : Color.red.opacity(0.18))
                .frame(width: 26, height: 26)
                .scaleEffect(isPaused ? 1 : 1 + min(level, 1) * 0.35)
                .animation(.easeOut(duration: 0.12), value: level)

            Image(systemName: isPaused ? "pause.fill" : "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPaused ? .orange : .red)
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: - Sound bars

/// The dynamic sound meter. Reads the recorder's rolling level window, mirrored
/// around the centre line so it reads as audio rather than a chart.
private struct SoundBars: View {
    let levels: [CGFloat]
    let isPaused: Bool

    /// Downsample the recorder's window to a bar count that fits the pill.
    private var bars: [CGFloat] {
        let target = 18
        guard levels.count > target else { return levels }
        let stride = CGFloat(levels.count) / CGFloat(target)
        return (0..<target).map { index in
            levels[min(Int(CGFloat(index) * stride), levels.count - 1)]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let values = bars
            let spacing: CGFloat = 2
            let width = max(
                (geometry.size.width - spacing * CGFloat(max(values.count - 1, 1))) / CGFloat(max(values.count, 1)),
                1.5
            )

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(isPaused ? Color.secondary.opacity(0.35) : Color.accentColor)
                        .frame(
                            width: width,
                            height: max(2.5, min(level, 1) * geometry.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.linear(duration: 0.06), value: levels)
        }
    }
}

// MARK: - Error

/// The one state that needs room: what went wrong and what to do about it.
private struct ErrorPill: View {
    @ObservedObject var controller: AppController
    let error: VoiceSmithError

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(error.errorDescription ?? "Something went wrong")
                        .font(.system(size: 12, weight: .semibold))
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                if controller.pendingAudio != nil {
                    Button("Retry") { controller.retryPending() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Discard") { controller.discardPending() }
                        .controlSize(.small)
                } else {
                    Button("OK") { controller.dismissError() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Spacer()
                if let url = error.systemSettingsURL {
                    Button("Open Settings") { NSWorkspace.shared.open(url) }
                        .controlSize(.small)
                }
                if let anchor = error.settingsAnchor {
                    Button("Providers…") {
                        NSApp.activate(ignoringOtherApps: true)
                        WindowRouter.shared.openSettings(anchor)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
        .background(PillBackground())
    }
}

// MARK: - Shared chrome

private struct PillBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
