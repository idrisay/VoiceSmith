import AppKit
import ApplicationServices
import Foundation
import UserNotifications

/// Clipboard, paste-back, and notifications. Each step is independently
/// switchable — a user who only wants the clipboard filled can turn off pasting.
enum Delivery {

    // MARK: - Clipboard

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Paste-back

    /// True when the app holds Accessibility rights, which auto-paste requires.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts for Accessibility once, with the system's own dialog.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// How the text actually reached the target — the panel reports this back.
    enum InsertionMethod {
        /// Written straight into the focused field. Leaves the clipboard untouched
        /// and doesn't depend on the app honouring a synthetic keystroke.
        case directInsertion
        /// Synthetic ⌘V into the frontmost app.
        case paste
    }

    /// Delivers text to the field that had focus when recording started.
    ///
    /// Writing to the element directly is preferred: it lands at the caret,
    /// replaces any selection, and survives apps that ignore synthetic keystrokes.
    /// Web views and Electron apps generally don't accept it, so ⌘V is the fallback.
    @discardableResult
    static func insert(_ text: String, into target: FocusedInput) throws -> InsertionMethod {
        guard hasAccessibilityPermission else {
            throw VoiceSmithError.accessibilityPermissionDenied
        }

        if let element = target.element,
           AXUIElementSetAttributeValue(
               element,
               kAXSelectedTextAttribute as CFString,
               text as CFTypeRef
           ) == .success {
            return .directInsertion
        }

        try paste(into: target.application)
        return .paste
    }

    /// Reactivates the app that was frontmost when recording started, then
    /// synthesises ⌘V. Throws rather than failing silently if rights are missing.
    static func paste(into target: NSRunningApplication?) throws {
        guard hasAccessibilityPermission else {
            throw VoiceSmithError.accessibilityPermissionDenied
        }

        if let target, !target.isActive {
            target.activate()
            // Give the target a moment to take focus before the keystroke lands.
            Thread.sleep(forTimeInterval: 0.12)
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw VoiceSmithError.accessibilityPermissionDenied
        }
        // Don't let our synthetic ⌘V re-trigger the global hotkey machinery.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { throw VoiceSmithError.accessibilityPermissionDenied }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Notifications

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
