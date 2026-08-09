import SwiftUI

/// The floating popup. Deliberately small: a mic, a live sound meter, a timer,
/// a language picker, and a stop button. Everything else — provider names, mode,
/// destination — is in the menu bar and Settings, not in the user's face
/// mid-sentence.
///
/// Language earns its place here because it is the one setting whose right value
/// is only apparent once you have started speaking: auto-detection reads the
/// audio, and on a short or accented recording it guesses wrong. The transcript
/// is not requested until recording stops, so choosing a language mid-sentence
/// still applies to the recording in progress.
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
            case .done where controller.offeredAction != nil:
                ActionOfferPill(controller: controller)
            case .done where controller.todoOutcome != nil:
                TodoOutcomePill(controller: controller)
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

            // Double-tap Option and double-tap Shift produce identical-looking
            // popups otherwise, and they do very different things with what you
            // say. Whichever one you reached for, you find out here — while
            // there's still time to hit Escape — rather than afterwards.
            if controller.intent == .todo {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 10, weight: .bold))
                    Text("To-do")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.tint)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }

            SoundBars(levels: recorder.levels, isPaused: recorder.isPaused)
                .frame(width: 96, height: 26)

            Text(timeString(recorder.duration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Divider().frame(height: 22)

            LanguageMenu(settings: settings)

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
        case .filingTasks: return "Finding to-dos…"
        case .done: return "Inserted"
        default: return "Working…"
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Detected action

/// An offer, not a decision.
///
/// By the time this appears the text is already in the user's field — the whole
/// point of the ordering. So doing nothing is a complete and correct response,
/// and it says so by dismissing itself. What it must not do is guess: "remind me
/// to book the room" and "schedule the room booking" are the same thought, so
/// both destinations are one click away and the model's guess only decides which
/// is emphasised.
private struct ActionOfferPill: View {
    @ObservedObject var controller: AppController

    /// Longer than the to-do confirmation, because this one asks for a decision
    /// rather than reporting a finished one.
    private static let secondsOnScreen = 7

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let action = controller.offeredAction {
                HStack(spacing: 7) {
                    Image(systemName: action.kind == .event ? "calendar" : "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(action.kind == .event ? "Sounds like an event" : "Sounds like a reminder")
                        .font(.system(size: 12, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let start = action.start {
                        Text(start, format: action.isAllDay
                             ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                             : .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    // The guess only decides which is emphasised; both stay one
                    // click away. Calendar is unavailable without a date —
                    // an event that happens at no particular time isn't one.
                    if action.kind == .event {
                        Button("Calendar") { controller.acceptOfferedAction(as: .event) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Reminder") { controller.acceptOfferedAction(as: .reminder) }
                            .controlSize(.small)
                    } else {
                        Button("Reminder") { controller.acceptOfferedAction(as: .reminder) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Calendar") { controller.acceptOfferedAction(as: .event) }
                            .controlSize(.small)
                            .disabled(action.start == nil)
                    }
                    Spacer()
                    Button("No thanks") { controller.declineOfferedAction() }
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
        .background(PillBackground())
        .onHover { hovering = $0 }
        .task(id: controller.offeredAction) {
            var remaining = Self.secondsOnScreen
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if hovering { continue }
                remaining -= 1
            }
            controller.declineOfferedAction()
        }
    }
}

// MARK: - To-do outcome

/// The one place the app shows its work before getting out of the way.
///
/// Everything else in this pipeline is reversible by ignoring it — text you
/// don't want, you delete. Reminders are different: they land in a list the user
/// keeps, and a wrong one has to be hunted down later in another app. So the
/// titles are shown and undo is right there.
///
/// It dismisses itself after a few seconds, because a confirmation you have to
/// dismiss by hand is a chore attached to every single capture. Hovering pauses
/// the countdown: reaching for Undo must never be a race against it.
private struct TodoOutcomePill: View {
    @ObservedObject var controller: AppController

    /// Long enough to read four task titles, short enough not to sit in the way.
    private static let secondsOnScreen = 4

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch controller.todoOutcome {
            case .filed(let tasks, let destination):
                filed(tasks, destination)
            case .nothingFound(let heard):
                nothingFound(heard)
            case nil:
                EmptyView()
            }
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
        .background(PillBackground())
        .onHover { hovering = $0 }
        .task(id: controller.todoOutcome) {
            var remaining = Self.secondsOnScreen
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                // Paused, not cancelled — the countdown resumes on leaving.
                if hovering { continue }
                remaining -= 1
            }
            controller.acknowledgeTodoOutcome()
        }
    }

    @ViewBuilder
    private func filed(_ tasks: [ExtractedTask], _ destination: AppController.Destination) -> some View {
        HStack(spacing: 7) {
            Image(systemName: destination == .calendar ? "calendar" : "checklist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
            Text(headline(tasks.count, destination))
                .font(.system(size: 12, weight: .semibold))
        }

        VStack(alignment: .leading, spacing: 3) {
            // Enough to recognise a mistake, not so many that the panel becomes
            // a list view. The rest are in Reminders.
            ForEach(tasks.prefix(4)) { task in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "circle")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                    Text(task.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    if let due = task.dueDate {
                        Text(due, format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if tasks.count > 4 {
                Text("and \(tasks.count - 4) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 13)
            }
        }

        HStack(spacing: 8) {
            Button("Undo") { controller.undoFiledTasks() }
                .controlSize(.small)
            Spacer()
            Button("Open \(destination.appName)") {
                NSWorkspace.shared.open(destination.url)
            }
            .controlSize(.small)
        }
    }

    private func headline(_ count: Int, _ destination: AppController.Destination) -> String {
        switch destination {
        case .calendar:  return "Added to Calendar"
        case .reminders: return count == 1 ? "1 to-do added" : "\(count) to-dos added"
        }
    }

    /// Says what was heard, because that is nearly always the explanation —
    /// a hallucinated "Thank you." off a silent recording, or a sentence that
    /// asked the app to do something instead of naming a task.
    @ViewBuilder
    private func nothingFound(_ heard: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No to-do in that")
                .font(.system(size: 12, weight: .semibold))
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Heard: \u{201C}\(heard)\u{201D}")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Say the task itself — \u{201C}call the dentist tomorrow\u{201D}.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Language

/// Bound straight to the setting Settings shows, so a choice made mid-recording
/// is the same choice made there and stays put until it's changed again. The
/// label stays a badge — "Auto", "EN", "TR" — because the full name would crowd
/// out the sound meter, and the menu spells it out anyway.
private struct LanguageMenu: View {
    @ObservedObject var settings: AppSettings

    @State private var hovering = false

    var body: some View {
        Menu {
            Picker("Language", selection: $settings.language) {
                Text(DictationLanguage.name(for: DictationLanguage.auto))
                    .tag(DictationLanguage.auto)
                Divider()
                ForEach(DictationLanguage.pinnable, id: \.code) { code, name in
                    Text(name).tag(code)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                Text(DictationLanguage.badge(for: settings.language))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(hovering ? 0.1 : 0.05)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Language — \(DictationLanguage.name(for: settings.language))")
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
