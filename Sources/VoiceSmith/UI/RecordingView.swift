import SwiftUI

/// The floating window. Shows a live waveform, the elapsed timer, and — always —
/// which providers are active, so the user knows whether audio is leaving the machine.
struct RecordingView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            switch controller.phase {
            case .recording:
                recordingBody
            case .transcribing, .improving:
                workingBody
            case .failed(let error):
                errorBody(error)
            case .idle, .done:
                workingBody
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Recording

    private var recordingBody: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(recorder.isPaused ? Color.orange : Color.red)
                    .frame(width: 9, height: 9)
                Text(recorder.isPaused ? "Paused" : "Recording")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(timeString(recorder.duration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Waveform(levels: recorder.levels, isPaused: recorder.isPaused)
                .frame(height: 44)

            HStack(spacing: 8) {
                if recorder.isPaused {
                    ControlButton(title: "Resume", symbol: "play.fill") { controller.resume() }
                } else {
                    ControlButton(title: "Pause", symbol: "pause.fill") { controller.pause() }
                }
                ControlButton(title: "Stop", symbol: "stop.fill", prominent: true) {
                    controller.stopAndProcess()
                }
                ControlButton(title: "Cancel", symbol: "xmark") { controller.cancel() }
            }

            providerFooter
        }
    }

    // MARK: - Working

    private var workingBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(phaseLabel)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Cancel") { controller.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !controller.statusDetail.isEmpty {
                Text(controller.statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            providerFooter
        }
    }

    private var phaseLabel: String {
        switch controller.phase {
        case .transcribing: return "Transcribing…"
        case .improving: return "Improving…"
        default: return "Working…"
        }
    }

    // MARK: - Error

    private func errorBody(_ error: VoiceSmithError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
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
                    Button("Discard audio") { controller.discardPending() }
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
                if error.settingsAnchor != nil {
                    Button("Providers…") {
                        NSApp.activate(ignoringOtherApps: true)
                        WindowRouter.shared.openSettings(.providers)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Footer

    /// Always visible during a session. The lock icon is the privacy signal.
    private var providerFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: settings.isFullyLocal ? "lock.fill" : "cloud.fill")
                .font(.system(size: 9))
                .foregroundStyle(settings.isFullyLocal ? .green : .secondary)
            Text(settings.speechProvider.displayName)
            if settings.improveAutomatically {
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                Text(settings.textProvider.displayName)
            }
            Spacer()
            Text(settings.activeMode.name)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Waveform

private struct Waveform: View {
    let levels: [CGFloat]
    let isPaused: Bool

    var body: some View {
        GeometryReader { geometry in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 2
            let barWidth = max((geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(isPaused ? Color.secondary.opacity(0.4) : Color.accentColor)
                        .frame(
                            width: barWidth,
                            height: max(3, level * geometry.size.height)
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.linear(duration: 0.05), value: levels)
        }
    }
}

// MARK: - Buttons

private struct ControlButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(prominent ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
        .controlSize(.small)
    }
}

/// Small shim so the two button styles can share one call site.
private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
