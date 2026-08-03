import AppKit
import SwiftUI

/// Owns every window. An accessory (menu-bar) app has no default window
/// management, so the floating panel, history, and settings are created here.
@MainActor
final class WindowRouter: ObservableObject {
    static let shared = WindowRouter()

    /// Which settings tab to reveal — errors deep-link into the pane that fixes them.
    @Published var settingsTab: SettingsTab = .general

    private var recordingPanel: NSPanel?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var controller: AppController!
    private var settings: AppSettings!
    private var store: NoteStore!

    private init() {}

    func configure(controller: AppController, settings: AppSettings, store: NoteStore) {
        self.controller = controller
        self.settings = settings
        self.store = store
    }

    // MARK: - Recording panel

    /// A non-activating floating panel, placed near the cursor. Non-activating
    /// matters: stealing focus would break paste-back into the previous app.
    func showRecordingPanel() {
        if recordingPanel == nil {
            let view = RecordingView(
                controller: controller,
                recorder: controller.recorder,
                settings: settings
            )
            let hosting = NSHostingController(rootView: view)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hosting
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            recordingPanel = panel
        }

        positionNearCursor(recordingPanel!)
        recordingPanel?.orderFrontRegardless()
    }

    func hideRecordingPanel() {
        recordingPanel?.orderOut(nil)
    }

    private func positionNearCursor(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return }

        let size = window.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 24)

        // Keep it fully on screen even when invoked near an edge.
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)
        window.setFrameOrigin(origin)
    }

    // MARK: - History

    func openHistory() {
        NSApp.activate(ignoringOtherApps: true)

        if historyWindow == nil {
            let view = HistoryView(controller: controller, store: store, settings: settings)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceSmith"
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Settings

    func openSettings(_ tab: SettingsTab = .general) {
        NSApp.activate(ignoringOtherApps: true)
        settingsTab = tab

        if settingsWindow == nil {
            let view = SettingsView(settings: settings, router: self)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceSmith Settings"
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Onboarding

    func openOnboardingIfNeeded() {
        guard !settings.hasCompletedOnboarding else { return }
        openSettings(.privacy)
        settings.hasCompletedOnboarding = true
    }
}
