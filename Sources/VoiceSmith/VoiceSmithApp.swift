import AppKit
import SwiftUI

@main
struct VoiceSmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                controller: delegate.controller,
                settings: delegate.settings
            )
        } label: {
            Image(systemName: delegate.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = AppSettings.shared
    lazy var store = NoteStore()
    lazy var controller = AppController(settings: settings, store: store)

    @Published var menuBarSymbol = "mic"

    private var phaseObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar utility: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        WindowRouter.shared.configure(controller: controller, settings: settings, store: store)
        controller.attachWindow(
            present: { WindowRouter.shared.showRecordingPanel() },
            dismiss: { WindowRouter.shared.hideRecordingPanel() }
        )

        registerShortcut()
        NotificationCenter.default.addObserver(
            forName: .shortcutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerShortcut() }
        }

        installEscapeMonitor()
        observePhase()

        Delivery.requestNotificationPermission()

        // Apply retention on launch, then drop references to files it removed.
        Storage.pruneAudio(retention: settings.audioRetention, keeping: store.referencedAudioPaths)
        store.reconcileAudioReferences()

        WindowRouter.shared.openOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcut.shared.unregister()
    }

    // MARK: - Shortcut

    private func registerShortcut() {
        GlobalShortcut.shared.register(
            keyCode: settings.shortcutKeyCode,
            modifiers: settings.shortcutModifiers
        ) { [weak self] in
            self?.controller.toggle()
        }
    }

    /// Escape cancels a recording from anywhere, without needing key focus in the panel.
    private func installEscapeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event } // kVK_Escape
            guard self.controller.phase.isBusy else { return event }
            self.controller.cancel()
            return nil
        }
    }

    /// Reflect state in the menu bar icon so the user can tell at a glance.
    private func observePhase() {
        phaseObserver = controller.$phase.sink { [weak self] phase in
            guard let self else { return }
            switch phase {
            case .recording: self.menuBarSymbol = "mic.fill"
            case .transcribing, .improving: self.menuBarSymbol = "waveform"
            case .failed: self.menuBarSymbol = "mic.badge.xmark"
            default: self.menuBarSymbol = "mic"
            }
        }
    }
}

// MARK: - Menu

private struct MenuBarContent: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings

    var body: some View {
        Button(controller.phase == .recording ? "Stop Recording" : "Start Recording") {
            controller.toggle()
        }
        .keyboardShortcut("r")

        if controller.phase == .recording {
            Button("Cancel Recording") { controller.cancel() }
        }

        Divider()

        Menu("Mode") {
            ForEach(settings.allModes) { mode in
                Button {
                    settings.modeID = mode.id
                } label: {
                    if mode.id == settings.modeID {
                        Label(mode.name, systemImage: "checkmark")
                    } else {
                        Text(mode.name)
                    }
                }
            }
        }

        Button("History…") { WindowRouter.shared.openHistory() }
            .keyboardShortcut("h")

        Divider()

        Text(statusLine)

        Button("Settings…") { WindowRouter.shared.openSettings() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit VoiceSmith") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        let shortcut = GlobalShortcut.describe(
            keyCode: settings.shortcutKeyCode,
            modifiers: settings.shortcutModifiers
        )
        let route = settings.improveAutomatically
            ? "\(settings.speechProvider.displayName) → \(settings.textProvider.displayName)"
            : settings.speechProvider.displayName
        return "\(shortcut)  ·  \(route)"
    }
}
