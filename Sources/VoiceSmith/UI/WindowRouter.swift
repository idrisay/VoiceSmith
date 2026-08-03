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
    private var onboardingWindow: NSWindow?
    private var onboardingCloseObserver: Any?

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

    /// A non-activating floating panel. Non-activating matters twice over: taking
    /// focus would both move the caret out of the user's text field and break
    /// insertion back into it.
    ///
    /// `caretRect` is the focused field's caret in Cocoa screen coordinates; the
    /// panel sits just below it, falling back to the pointer when it's nil.
    func showRecordingPanel(near caretRect: CGRect? = nil) {
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

        position(recordingPanel!, near: caretRect)
        recordingPanel?.orderFrontRegardless()
    }

    func hideRecordingPanel() {
        recordingPanel?.orderOut(nil)
    }

    private func position(_ window: NSWindow, near caretRect: CGRect?) {
        let size = window.frame.size
        let anchor: CGPoint
        let gap: CGFloat

        if let caretRect {
            // Centre under the caret, clear of the text line itself.
            anchor = CGPoint(x: caretRect.midX, y: caretRect.minY)
            gap = 10
        } else {
            anchor = NSEvent.mouseLocation
            gap = 24
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) })
                ?? NSScreen.main
        else { return }

        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - gap)

        // If there's no room below (caret near the bottom of the screen), flip above it.
        let visible = screen.visibleFrame
        if origin.y < visible.minY + 12 {
            let topOfAnchor = caretRect?.maxY ?? anchor.y
            origin.y = topOfAnchor + gap
        }

        // Keep it fully on screen even when invoked near an edge.
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
        openOnboarding()
    }

    func openOnboarding() {
        NSApp.activate(ignoringOtherApps: true)

        if onboardingWindow == nil {
            let view = OnboardingView(settings: settings) { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceSmith Setup"
            window.titlebarAppearsTransparent = true
            window.contentViewController = NSHostingController(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false

            // Closing the window counts as finishing. Re-showing it on every
            // launch until the user reaches the last step would be nagware —
            // Settings › General has a "Run again…" button for a second pass.
            onboardingCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.settings.hasCompletedOnboarding = true
                    self?.onboardingWindow = nil
                }
            }

            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}
