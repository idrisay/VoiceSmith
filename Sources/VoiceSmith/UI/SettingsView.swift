import AppKit
import ServiceManagement
import SwiftUI

/// Permission state and destination list for to-do filing.
///
/// The list is read from EventKit on appear rather than held in the settings
/// object, because it changes in another app: lists get renamed and deleted in
/// Reminders, and a stale copy here would offer somewhere that no longer exists.
private struct RemindersSettings: View {
    @ObservedObject var settings: AppSettings

    @State private var lists: [(id: String, title: String)] = []
    @State private var isAuthorized = RemindersService.shared.isAuthorized

    var body: some View {
        Group {
            if isAuthorized {
                Picker("To-do list", selection: $settings.reminderListID) {
                    Text("Default list").tag("")
                    if !lists.isEmpty { Divider() }
                    ForEach(lists, id: \.id) { list in
                        Text(list.title).tag(list.id)
                    }
                }
                Text("After each dictation, VoiceSmith asks the text model for any action items you mentioned and adds them here. Nothing is added when you weren't describing something to do. You can undo straight from the popup.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Adding to-dos needs access to Reminders.")
                        .font(.system(size: 11))
                    Button("Grant…") {
                        Task { @MainActor in
                            await RemindersService.shared.requestAccess()
                            refresh()
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        isAuthorized = RemindersService.shared.isAuthorized
        lists = isAuthorized ? RemindersService.shared.availableLists() : []
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var router: WindowRouter

    var body: some View {
        TabView(selection: $router.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                pane(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .padding(16)
        .frame(width: 600, height: 460)
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralPane(settings: settings)
        case .providers: ProvidersPane(settings: settings)
        case .modes: ModesPane(settings: settings)
        case .shortcuts: ShortcutPane(settings: settings)
        case .privacy: PrivacyPane(settings: settings)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("After transcription") {
                Toggle("Improve with AI", isOn: $settings.improveAutomatically)
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
                Toggle("Insert into the focused text field", isOn: $settings.autoPaste)
                Toggle("Show a notification", isOn: $settings.showNotification)

                Toggle("Double-tap Option captures a to-do", isOn: $settings.triggerTodoOnDoubleOption)
                Toggle("Add to-dos to Reminders from every dictation", isOn: $settings.addToTaskList)
                if settings.addToTaskList || settings.triggerTodoOnDoubleOption {
                    RemindersSettings(settings: settings)
                }

                if settings.autoPaste {
                    if Delivery.hasAccessibilityPermission {
                        Text("When a text field has focus, the result is written straight into it at the caret. Otherwise it goes to the clipboard only.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Inserting needs Accessibility access.")
                                .font(.system(size: 11))
                            Button("Grant…") { Delivery.requestAccessibilityPermission() }
                                .controlSize(.small)
                        }
                    }
                }
            }

            Section("Startup") {
                LaunchAtLoginToggle()
                HStack {
                    Text("Setup assistant")
                    Spacer()
                    Button("Run again…") { WindowRouter.shared.openOnboarding() }
                        .controlSize(.small)
                }
            }

            Section("Recording") {
                Picker("Mode", selection: $settings.modeID) {
                    ForEach(settings.allModes) { mode in
                        Text(mode.name).tag(mode.id)
                    }
                }
                Picker("Language", selection: $settings.language) {
                    Text(DictationLanguage.name(for: DictationLanguage.auto))
                        .tag(DictationLanguage.auto)
                    Divider()
                    ForEach(DictationLanguage.pinnable, id: \.code) { code, name in
                        Text(name).tag(code)
                    }
                }
                Picker("Maximum length", selection: $settings.maxRecordingSeconds) {
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("30 minutes").tag(1800)
                }
            }
        }
        .formStyle(.grouped)
    }

}

// MARK: - Providers

private struct ProvidersPane: View {
    @ObservedObject var settings: AppSettings
    @State private var ollamaModels: [String] = []

    var body: some View {
        Form {
            Section("Speech to text") {
                Picker("Provider", selection: $settings.speechProvider) {
                    ForEach(SpeechProviderKind.allCases) { kind in
                        Text(kind.displayName + (kind.isLocal ? " (local)" : "")).tag(kind)
                    }
                }
                .onChange(of: settings.speechProvider) { _, new in
                    settings.speechModel = new.defaultModel
                }

                TextField("Model", text: $settings.speechModel)

                if let account = settings.speechProvider.keychainAccount {
                    APIKeyField(account: account, providerName: settings.speechProvider.displayName)
                }

                if settings.speechProvider == .whisperCPP {
                    WhisperPaths()
                }
            }

            Section("Text improvement") {
                Picker("Provider", selection: $settings.textProvider) {
                    ForEach(TextProviderKind.allCases) { kind in
                        Text(kind.displayName + (kind.isLocal ? " (local)" : "")).tag(kind)
                    }
                }
                .onChange(of: settings.textProvider) { _, new in
                    settings.textModel = new.defaultModel
                    if new == .ollama { refreshOllama() }
                }

                if settings.textProvider == .ollama && !ollamaModels.isEmpty {
                    Picker("Model", selection: $settings.textModel) {
                        ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    TextField("Model", text: $settings.textModel)
                }

                if let account = settings.textProvider.keychainAccount {
                    APIKeyField(account: account, providerName: settings.textProvider.displayName)
                }

                if settings.textProvider == .ollama {
                    HStack {
                        Button("Refresh installed models") { refreshOllama() }
                            .controlSize(.small)
                        if ollamaModels.isEmpty {
                            Text("Ollama isn't reachable at localhost:11434.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if settings.textProvider == .ollama { refreshOllama() } }
    }

    private func refreshOllama() {
        Task {
            let models = await OllamaProvider.installedModels(
                baseURL: TextProviderKind.ollama.defaultBaseURL
            )
            await MainActor.run { ollamaModels = models }
        }
    }
}

/// `SMAppService` is the login-item API; it registers the running bundle, so it
/// only behaves correctly from a built `.app`, not from `swift run`.
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var failure: String?

    var body: some View {
        Toggle("Launch VoiceSmith at login", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    failure = nil
                } catch {
                    failure = error.localizedDescription
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
        if let failure {
            Text(failure)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }
    }
}

/// Keys are write-only in the UI: we show whether one is stored, never the value.
private struct APIKeyField: View {
    let account: String
    let providerName: String

    @State private var entry = ""
    @State private var stored = false

    var body: some View {
        HStack {
            SecureField("API key", text: $entry)
                .onSubmit(save)
            if stored && entry.isEmpty {
                Label("Stored", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Button("Remove") {
                    Keychain.remove(account)
                    stored = false
                }
                .controlSize(.small)
            } else {
                Button("Save", action: save)
                    .controlSize(.small)
                    .disabled(entry.isEmpty)
            }
        }
        .onAppear { stored = Keychain.has(account) }
        .onChange(of: account) { _, new in
            entry = ""
            stored = Keychain.has(new)
        }
    }

    private func save() {
        guard !entry.isEmpty else { return }
        Keychain.set(entry, for: account)
        entry = ""
        stored = true
    }
}

private struct WhisperPaths: View {
    @AppStorage("whisperBinaryPath") private var binaryPath = ""
    @AppStorage("whisperModelPath") private var modelPath = ""

    var body: some View {
        TextField("whisper-cli path", text: $binaryPath, prompt: Text(WhisperCPPProvider.discoverBinary() ?? "/opt/homebrew/bin/whisper-cli"))
        HStack {
            TextField("Model file (.bin)", text: $modelPath)
            Button("Choose…") { chooseModel() }
                .controlSize(.small)
        }
    }

    private func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            modelPath = url.path
        }
    }
}

// MARK: - Modes

private struct ModesPane: View {
    @ObservedObject var settings: AppSettings
    @State private var selection: String?

    private var selectedMode: ImprovementMode? {
        settings.allModes.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            List(settings.allModes, selection: $selection) { mode in
                HStack {
                    Text(mode.name)
                    Spacer()
                    if !mode.isBuiltIn {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(mode.id)
            }
            .frame(minWidth: 160, maxWidth: 200)

            VStack(alignment: .leading, spacing: 10) {
                if let mode = selectedMode {
                    Text(mode.name).font(.headline)
                    Text(mode.isBuiltIn ? "Built-in mode. Duplicate it to change the prompt." : "Custom mode.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if mode.isBuiltIn {
                        Text(mode.prompt)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextEditor(text: binding(for: mode))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minHeight: 140)
                    }

                    HStack {
                        Button("Duplicate") { duplicate(mode) }
                        if !mode.isBuiltIn {
                            Button("Delete", role: .destructive) {
                                settings.customModes.removeAll { $0.id == mode.id }
                                selection = ImprovementMode.builtIns.first?.id
                            }
                        }
                        Spacer()
                    }
                    .controlSize(.small)
                } else {
                    Text("Select a mode.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(minWidth: 320)
        }
        .onAppear { selection = selection ?? settings.modeID }
    }

    private func binding(for mode: ImprovementMode) -> Binding<String> {
        Binding(
            get: { settings.customModes.first { $0.id == mode.id }?.prompt ?? "" },
            set: { newValue in
                guard let index = settings.customModes.firstIndex(where: { $0.id == mode.id }) else { return }
                settings.customModes[index].prompt = newValue
            }
        )
    }

    private func duplicate(_ mode: ImprovementMode) {
        let copy = ImprovementMode(
            id: UUID().uuidString,
            name: mode.name + " Copy",
            isBuiltIn: false,
            prompt: mode.prompt
        )
        settings.customModes.append(copy)
        selection = copy.id
    }
}

// MARK: - Shortcut

private struct ShortcutPane: View {
    @ObservedObject var settings: AppSettings
    @State private var recording = false

    var body: some View {
        Form {
            Section("Double-tap Shift") {
                Toggle("Start and stop by tapping Shift twice", isOn: $settings.triggerOnDoubleShift)
                    .onChange(of: settings.triggerOnDoubleShift) { _, _ in
                        NotificationCenter.default.post(name: .shortcutChanged, object: nil)
                    }

                if settings.triggerOnDoubleShift {
                    if Delivery.hasAccessibilityPermission {
                        Text("Taps must land within about a third of a second. Holding Shift, or using it with another key, is ignored — so typing capitals never triggers it.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Needs Accessibility access — a modifier tap can't be a system shortcut.")
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Grant…") { Delivery.requestAccessibilityPermission() }
                                .controlSize(.small)
                        }
                    }

                    Text("Some editors, including the JetBrains IDEs, use double-tap Shift themselves. In those apps both will fire.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Key combination") {
                HStack {
                    Text("Start / stop recording")
                    Spacer()
                    Button {
                        recording.toggle()
                    } label: {
                        Text(recording
                             ? "Press keys…"
                             : GlobalShortcut.describe(
                                keyCode: settings.shortcutKeyCode,
                                modifiers: settings.shortcutModifiers))
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.bordered)
                }
                Text("Works from any application. Press the shortcut again to stop, or Escape to cancel.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if let conflict = GlobalShortcut.systemConflict(
                    keyCode: settings.shortcutKeyCode,
                    modifiers: settings.shortcutModifiers
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("macOS reserves this for **\(conflict)** and handles it before VoiceSmith ever sees it.")
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Either pick a different combination above, or turn the system one off in Keyboard Shortcuts to free it up.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Keyboard Shortcuts…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .background(ShortcutCatcher(isActive: $recording) { keyCode, modifiers in
            settings.shortcutKeyCode = keyCode
            settings.shortcutModifiers = modifiers
            recording = false
            NotificationCenter.default.post(name: .shortcutChanged, object: nil)
        })
    }
}

/// Captures the next key-down while the user is assigning a shortcut.
private struct ShortcutCatcher: NSViewRepresentable {
    @Binding var isActive: Bool
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onCapture: onCapture)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var monitor: Any?

        func update(isActive: Bool, onCapture: @escaping (UInt32, UInt32) -> Void) {
            if isActive, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let modifiers = GlobalShortcut.carbonModifiers(from: event.modifierFlags)
                    guard modifiers != 0 else { return event } // require at least one modifier
                    onCapture(UInt32(event.keyCode), modifiers)
                    return nil
                }
            } else if !isActive, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Audio retention") {
                Picker("Keep recordings", selection: $settings.audioRetention) {
                    ForEach(AudioRetention.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.inline)
                Text(settings.audioRetention.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Where your words go") {
                HStack(spacing: 8) {
                    Image(systemName: settings.isFullyLocal ? "lock.fill" : "cloud.fill")
                        .foregroundStyle(settings.isFullyLocal ? .green : .orange)
                    Text(settings.isFullyLocal
                         ? "Nothing leaves this Mac. Both providers run locally."
                         : "Audio or text is sent to a cloud provider you've configured.")
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("""
                VoiceSmith stores notes only on this Mac and runs no server of its own. \
                Cloud providers are your own accounts under your own agreements with them; \
                requests go straight from this app to the provider. API keys are kept in the \
                macOS Keychain and never written to logs. There is no telemetry.
                """)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Reveal note storage in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Storage.rootDirectory.path)
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
    }
}

extension Notification.Name {
    static let shortcutChanged = Notification.Name("VoiceSmith.shortcutChanged")
}
