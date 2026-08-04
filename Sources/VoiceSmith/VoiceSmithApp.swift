import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct VoiceSmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                controller: delegate.controller,
                settings: delegate.settings,
                delegate: delegate
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
    /// Non-nil when the configured shortcut will never reach us.
    @Published var shortcutProblem: String?

    private var phaseObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar utility: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        WindowRouter.shared.configure(controller: controller, settings: settings, store: store)
        controller.attachWindow(
            present: { caretRect in WindowRouter.shared.showRecordingPanel(near: caretRect) },
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

        observePhase()

        Delivery.requestNotificationPermission()

        // Apply retention on launch, then drop references to files it removed.
        Storage.pruneAudio(retention: settings.audioRetention, keeping: store.referencedAudioPaths)
        store.reconcileAudioReferences()

        WindowRouter.shared.openOnboardingIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcut.shared.unregister()
        GlobalShortcut.cancel.unregister()
    }

    // MARK: - Shortcut

    private func registerShortcut() {
        let claimed = GlobalShortcut.shared.register(
            keyCode: settings.shortcutKeyCode,
            modifiers: settings.shortcutModifiers
        ) { [weak self] in
            self?.controller.toggle()
        }

        let reserved = GlobalShortcut.systemConflict(
            keyCode: settings.shortcutKeyCode,
            modifiers: settings.shortcutModifiers
        )

        // A reserved combination registers "successfully" but the system handler
        // wins, so check both conditions.
        if let reserved {
            shortcutProblem = "macOS uses this shortcut for \(reserved)."
        } else if !claimed {
            shortcutProblem = "Another app already uses this shortcut."
        } else {
            shortcutProblem = nil
        }
    }

    /// Escape cancels, from whatever app the user is actually in.
    ///
    /// Claimed only while a session is live, because grabbing bare Escape
    /// system-wide the rest of the time would break every other app's use of it.
    private func setEscapeCapture(active: Bool) {
        guard active else {
            GlobalShortcut.cancel.unregister()
            return
        }
        GlobalShortcut.cancel.register(
            keyCode: UInt32(kVK_Escape),
            modifiers: 0
        ) { [weak self] in
            self?.controller.cancel()
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
            // Bare Escape is only ours while something is actually in flight.
            self.setEscapeCapture(active: phase.isBusy)
            // Let SwiftUI lay the new state out before measuring it.
            DispatchQueue.main.async { WindowRouter.shared.resizeRecordingPanel() }
        }
    }
}

// MARK: - Menu

private struct MenuBarContent: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings
    @ObservedObject var delegate: AppDelegate

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

        if let problem = delegate.shortcutProblem {
            Button("⚠︎ \(problem) Choose another…") {
                WindowRouter.shared.openSettings(.shortcuts)
            }
        }

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
