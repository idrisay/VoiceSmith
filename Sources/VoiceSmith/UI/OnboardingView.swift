import AVFoundation
import AppKit
import Speech
import SwiftUI

/// First-run setup. Walks the user through the two provider choices, the keys
/// those choices need, the permissions the app can't work without, and the audio
/// retention decision — which the spec deliberately surfaces here rather than
/// burying it in preferences.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onFinish: () -> Void

    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, speech, text, permissions, privacy, ready

        var title: String {
            switch self {
            case .welcome: return "Welcome to VoiceSmith"
            case .speech: return "Choose how speech is transcribed"
            case .text: return "Choose how text is improved"
            case .permissions: return "Grant permissions"
            case .privacy: return "Decide what happens to recordings"
            case .ready: return "You're set up"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(width: 620, height: 540)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 15, weight: .semibold))
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Circle()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { advance(-1) }
            }
            Spacer()
            if step != .ready {
                Button("Skip setup") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button(step == .ready ? "Start using VoiceSmith" : "Continue") {
                step == .ready ? finish() : advance(1)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func advance(_ delta: Int) {
        let next = step.rawValue + delta
        guard let target = Step(rawValue: next) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { step = target }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .speech: SpeechSetupStep(settings: settings)
        case .text: TextSetupStep(settings: settings)
        case .permissions: PermissionsStep(settings: settings)
        case .privacy: PrivacyStep(settings: settings)
        case .ready: readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VoiceSmith turns what you say into finished writing, without leaving the app you're already in.")
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 12) {
                NumberedStep(number: "1", text: "Tap **\(shortcutDescription)** from anywhere.")
                NumberedStep(number: "2", text: "Speak. Do it again when you're done.")
                NumberedStep(number: "3", text: "The polished text lands in whatever text field you were in.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Text("Setup takes about a minute. You can change any of it later in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("VoiceSmith is running in your menu bar", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13, weight: .medium))

            VStack(alignment: .leading, spacing: 8) {
                SummaryRow(label: "Shortcut", value: shortcutDescription)
                SummaryRow(label: "Transcription", value: settings.speechProvider.displayName)
                SummaryRow(
                    label: "Improvement",
                    value: settings.improveAutomatically ? settings.textProvider.displayName : "Off"
                )
                SummaryRow(label: "Mode", value: settings.activeMode.name)
                SummaryRow(label: "Recordings", value: settings.audioRetention.displayName)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            if settings.isFullyLocal {
                Label(
                    "Everything runs on this Mac. No audio or text leaves the device.",
                    systemImage: "lock.fill"
                )
                .font(.system(size: 12))
                .foregroundStyle(.green)
            }

            Text("Try it now: click into any text field and \(shortcutDescription).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var shortcutDescription: String {
        settings.triggerOnDoubleShift
            ? "double-tap ⇧"
            : GlobalShortcut.describe(
                keyCode: settings.shortcutKeyCode,
                modifiers: settings.shortcutModifiers
            )
    }

    private struct NumberedStep: View {
        let number: String
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Text(number)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                Text(.init(text))
                    .font(.system(size: 12))
            }
        }
    }

    private struct SummaryRow: View {
        let label: String
        let value: String

        var body: some View {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
}

// MARK: - Speech step

private struct SpeechSetupStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This turns your voice into raw text.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ProviderChoice(
                title: "On this Mac",
                subtitle: "No key, no cost, works offline.",
                options: SpeechProviderKind.allCases.filter(\.isLocal),
                selection: $settings.speechProvider,
                label: \.displayName
            )

            ProviderChoice(
                title: "Cloud",
                subtitle: "Usually more accurate. Needs an API key from your own account.",
                options: SpeechProviderKind.allCases.filter { !$0.isLocal },
                selection: $settings.speechProvider,
                label: \.displayName
            )

            if let account = settings.speechProvider.keychainAccount {
                Divider()
                KeyEntry(
                    account: account,
                    providerName: settings.speechProvider.displayName,
                    helpURL: Self.signupURL(settings.speechProvider)
                )
            } else if settings.speechProvider == .whisperCPP {
                Divider()
                Label(
                    "Whisper.cpp needs a binary and a model file. Set both in Settings › Providers after setup.",
                    systemImage: "info.circle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            } else {
                Divider()
                Label("Nothing else to configure — Apple Speech needs no key.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
        }
        .onChange(of: settings.speechProvider) { _, new in
            settings.speechModel = new.defaultModel
        }
    }

    static func signupURL(_ kind: SpeechProviderKind) -> URL? {
        switch kind {
        case .openAIWhisper: return URL(string: "https://platform.openai.com/api-keys")
        case .groqWhisper: return URL(string: "https://console.groq.com/keys")
        case .deepgram: return URL(string: "https://console.deepgram.com/")
        case .assemblyAI: return URL(string: "https://www.assemblyai.com/app/account")
        default: return nil
        }
    }
}

// MARK: - Text step

private struct TextSetupStep: View {
    @ObservedObject var settings: AppSettings
    @State private var ollamaModels: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Improve transcripts with AI", isOn: $settings.improveAutomatically)
                .font(.system(size: 13, weight: .medium))
            Text("With this off, VoiceSmith delivers the raw transcript and never contacts a text model.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if settings.improveAutomatically {
                Divider()

                ProviderChoice(
                    title: "On this Mac",
                    subtitle: "No key, no cost, works offline. Needs Ollama or LM Studio running.",
                    options: TextProviderKind.allCases.filter(\.isLocal),
                    selection: $settings.textProvider,
                    label: \.displayName
                )

                ProviderChoice(
                    title: "Cloud",
                    subtitle: "Best quality. Needs an API key from your own account.",
                    options: TextProviderKind.allCases.filter { !$0.isLocal },
                    selection: $settings.textProvider,
                    label: \.displayName
                )

                Divider()

                HStack {
                    Text("Model").font(.system(size: 12))
                    if settings.textProvider == .ollama && !ollamaModels.isEmpty {
                        Picker("", selection: $settings.textModel) {
                            ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    } else {
                        TextField("", text: $settings.textModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if let account = settings.textProvider.keychainAccount {
                    KeyEntry(
                        account: account,
                        providerName: settings.textProvider.displayName,
                        helpURL: Self.signupURL(settings.textProvider),
                        validator: { try await validateTextProvider() }
                    )
                } else {
                    LocalServerHint(kind: settings.textProvider, models: ollamaModels, refresh: refreshOllama)
                }
            }
        }
        .onChange(of: settings.textProvider) { _, new in
            settings.textModel = new.defaultModel
            if new == .ollama { refreshOllama() }
        }
        .onAppear { if settings.textProvider == .ollama { refreshOllama() } }
    }

    /// Round-trips a tiny string through the configured model. Cheap, and it
    /// catches a bad key or a wrong model name now rather than mid-dictation.
    private func validateTextProvider() async throws {
        let provider = try ProviderFactory.text(settings)
        _ = try await provider.improve(
            "this are a test",
            mode: ImprovementMode.builtIns.first { $0.id == "verbatim" } ?? ImprovementMode.builtIns[0],
            language: "en-US"
        )
    }

    private func refreshOllama() {
        Task {
            let models = await OllamaProvider.installedModels(
                baseURL: TextProviderKind.ollama.defaultBaseURL
            )
            await MainActor.run {
                ollamaModels = models
                if let first = models.first, !models.contains(settings.textModel) {
                    settings.textModel = first
                }
            }
        }
    }

    static func signupURL(_ kind: TextProviderKind) -> URL? {
        switch kind {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .googleGemini: return URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .deepSeek: return URL(string: "https://platform.deepseek.com/api_keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        default: return nil
        }
    }
}

private struct LocalServerHint: View {
    let kind: TextProviderKind
    let models: [String]
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if models.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(kind.displayName) isn't reachable at \(kind.defaultBaseURL).")
                        .font(.system(size: 11))
                    Text(kind == .ollama
                         ? "Install it from ollama.com, then run `ollama pull qwen3:8b`."
                         : "Start the local server and load a model.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check again", action: refresh).controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(kind.displayName) is running with \(models.count) model\(models.count == 1 ? "" : "s") installed.")
                    .font(.system(size: 11))
                Spacer()
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Reusable provider picker

private struct ProviderChoice<Kind: Hashable & Identifiable>: View {
    let title: String
    let subtitle: String
    let options: [Kind]
    @Binding var selection: Kind
    let label: KeyPath<Kind, String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                ForEach(options) { option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            Text(option[keyPath: label])
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - API key entry

/// Saves straight to the Keychain and can verify the key before the user moves on.
private struct KeyEntry: View {
    let account: String
    let providerName: String
    var helpURL: URL?
    var validator: (() async throws -> Void)?

    @State private var entry = ""
    @State private var stored = false
    @State private var state: ValidationState = .idle

    private enum ValidationState: Equatable {
        case idle, checking, ok, failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(providerName) API key")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if let helpURL {
                    Link("Get a key ↗", destination: helpURL)
                        .font(.system(size: 11))
                }
            }

            HStack(spacing: 8) {
                SecureField(stored ? "Stored in Keychain — type to replace" : "Paste your key", text: $entry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)

                if !entry.isEmpty {
                    Button("Save", action: save)
                } else if stored {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Button("Remove") {
                        Keychain.remove(account)
                        stored = false
                        state = .idle
                    }
                    .controlSize(.small)
                }

                if stored, let validator {
                    Button("Test") { check(validator) }
                        .disabled(state == .checking)
                        .controlSize(.small)
                }
            }

            statusLine

            Text("Stored in your macOS Keychain. VoiceSmith sends requests straight to \(providerName) — there's no server in between.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { stored = Keychain.has(account) }
        .onChange(of: account) { _, new in
            entry = ""
            state = .idle
            stored = Keychain.has(new)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .ok:
            Label("Key works.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        guard !entry.isEmpty else { return }
        Keychain.set(entry, for: account)
        entry = ""
        stored = true
        state = .idle
        if let validator { check(validator) }
    }

    private func check(_ validator: @escaping () async throws -> Void) {
        state = .checking
        Task {
            do {
                try await validator()
                await MainActor.run { state = .ok }
            } catch let error as VoiceSmithError {
                await MainActor.run {
                    state = .failed(error.errorDescription ?? "The key didn't work.")
                }
            } catch {
                await MainActor.run { state = .failed(error.localizedDescription) }
            }
        }
    }
}

// MARK: - Permissions step

private struct PermissionsStep: View {
    @ObservedObject var settings: AppSettings

    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var speech = SFSpeechRecognizer.authorizationStatus()
    @State private var accessibility = Delivery.hasAccessibilityPermission

    // These grants happen in System Settings, which sends no notification —
    // poll while this step is on screen so the checkmarks update live.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionRow(
                title: "Microphone",
                detail: "Required. Without it VoiceSmith can't record anything.",
                granted: microphone == .authorized,
                denied: microphone == .denied || microphone == .restricted,
                action: requestMicrophone,
                settingsURL: VoiceSmithError.microphonePermissionDenied.systemSettingsURL
            )

            if settings.speechProvider == .appleSpeech {
                PermissionRow(
                    title: "Speech Recognition",
                    detail: "Required for Apple Speech, which transcribes on this Mac.",
                    granted: speech == .authorized,
                    denied: speech == .denied || speech == .restricted,
                    action: requestSpeech,
                    settingsURL: VoiceSmithError.speechPermissionDenied.systemSettingsURL
                )
            }

            PermissionRow(
                title: "Accessibility",
                detail: settings.triggerOnDoubleShift
                    ? "Required for double-tap Shift, and for writing the result into the field you're in. Without it, use the key combination and paste manually."
                    : "Optional. Lets VoiceSmith see which text field you're in and write the result into it. Without it you'll get the text on the clipboard and paste it yourself.",
                granted: accessibility,
                denied: false,
                action: { Delivery.requestAccessibilityPermission() },
                settingsURL: VoiceSmithError.accessibilityPermissionDenied.systemSettingsURL
            )

            Text("macOS asks for each of these itself. If you've already denied one, the button opens System Settings instead.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .onReceive(poll) { _ in
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            speech = SFSpeechRecognizer.authorizationStatus()
            accessibility = Delivery.hasAccessibilityPermission
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in microphone = AVCaptureDevice.authorizationStatus(for: .audio) }
        }
    }

    private func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in speech = status }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let denied: Bool
    let action: () -> Void
    let settingsURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if granted {
                Text("Granted").font(.system(size: 11)).foregroundStyle(.green)
            } else if denied, let settingsURL {
                Button("Open Settings") { NSWorkspace.shared.open(settingsURL) }
                    .controlSize(.small)
            } else {
                Button("Grant", action: action).controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Privacy step

private struct PrivacyStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VoiceSmith keeps every note on this Mac. There's no account, no server of ours, and no telemetry.")
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text("Audio recordings").font(.system(size: 12, weight: .semibold))
                ForEach(AudioRetention.allCases) { option in
                    Button {
                        settings.audioRetention = option
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: settings.audioRetention == option
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(settings.audioRetention == option ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.displayName).font(.system(size: 12))
                                Text(option.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(
                                settings.audioRetention == option
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.secondary.opacity(0.06)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if !settings.isFullyLocal {
                Label(
                    "Your transcripts are sent to the cloud providers you picked, using your own accounts under your agreements with them.",
                    systemImage: "cloud"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
