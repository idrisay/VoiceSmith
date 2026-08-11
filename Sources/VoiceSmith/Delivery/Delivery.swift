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

    /// Why the last direct-write attempt was or wasn't believed. Recorded because
    /// a silent no-op write is indistinguishable from success without it.
    static var lastAttemptDetail = ""

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
    static func insert(_ text: String, into target: FocusedInput, copiedToClipboard: Bool) throws -> InsertionMethod {
        guard hasAccessibilityPermission else {
            throw VoiceSmithError.accessibilityPermissionDenied
        }

        // A direct write is preferable when it works — it lands at the caret and
        // leaves the clipboard alone. But its return value cannot be trusted:
        // Electron apps (VS Code, Slack, Discord) accept the call, report
        // success, and do nothing. Believing them meant never falling back, so
        // the text silently went only to the clipboard.
        //
        // So verify the document actually changed, and treat "can't tell" as failure.
        if let element = target.element {
            // Replacing a selection of exactly the dictated text's length leaves
            // the character count untouched, so counting alone would read a
            // perfectly good write as a failure and paste a duplicate on top of
            // text that was already correct. Only in that narrow case is the
            // whole value worth pulling across to compare.
            let selectionLength = selectedText(of: element)?.count ?? 0
            let lengthPreserving = selectionLength > 0 && selectionLength == text.count
            let valueBefore = lengthPreserving ? value(of: element) : nil

            let before = characterCount(of: element)
            let wrote = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            ) == .success
            let after = characterCount(of: element)

            lastAttemptDetail = "write=\(wrote) chars \(before.map(String.init) ?? "?")→\(after.map(String.init) ?? "?")"
                + (lengthPreserving ? " (same-length selection)" : "")

            if wrote {
                if let before, let after, after != before {
                    return .directInsertion
                }
                // Same length either way: the contents settle it.
                if let valueBefore, let valueAfter = value(of: element), valueAfter != valueBefore {
                    lastAttemptDetail += " value-changed"
                    return .directInsertion
                }
            }
        } else {
            lastAttemptDetail = "no element"
        }

        // ⌘V pastes whatever is on the clipboard, so the text has to be there
        // first. When the user has clipboard copying switched off, borrow it and
        // hand it back — pasting stale clipboard contents would be worse than
        // not pasting at all.
        let restore: String? = copiedToClipboard
            ? nil
            : NSPasteboard.general.string(forType: .string)
        if !copiedToClipboard {
            copyToClipboard(text)
        }

        let pasteDelay = try paste(into: target.application)

        if let restore {
            // Give the paste time to land before putting the clipboard back —
            // measured from when the keystroke actually goes out, not from now.
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay + 0.4) {
                copyToClipboard(restore)
            }
        }
        return .paste
    }

    /// Length of the field's contents, used to confirm a direct write landed.
    /// Returns nil when the app won't tell us — which itself means its
    /// accessibility support is too partial to trust, so callers treat nil as
    /// "assume the write failed" and paste instead.
    private static func characterCount(of element: AXUIElement) -> Int? {
        // Cheap and widely implemented — avoids pulling a whole document across.
        var count: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXNumberOfCharactersAttribute as CFString, &count
        ) == .success, let number = count as? Int {
            return number
        }

        if let string = value(of: element) {
            return string.count
        }

        return nil
    }

    /// The element's whole contents, when it will hand them over.
    private static func value(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXValueAttribute as CFString, &value
        ) == .success else { return nil }
        return value as? String
    }

    /// The text currently selected in the element, if any.
    private static func selectedText(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value
        ) == .success else { return nil }
        return value as? String
    }

    /// How long the app waits for a reactivated target to take focus. Long
    /// enough that the keystroke doesn't land in the previous app.
    private static let activationDelay: TimeInterval = 0.12

    /// Reactivates the app that was frontmost when recording started, then
    /// synthesises ⌘V. Throws rather than failing silently if rights are missing.
    ///
    /// Returns how long the keystroke was deferred by. Reactivation needs a
    /// moment to take effect, and this runs on the main actor — sleeping through
    /// it froze the app's own UI, the recording panel included, on every paste
    /// fallback. So the wait is scheduled rather than slept.
    @discardableResult
    static func paste(into target: NSRunningApplication?) throws -> TimeInterval {
        guard hasAccessibilityPermission else {
            throw VoiceSmithError.accessibilityPermissionDenied
        }

        // Built up front so a failure is still thrown to the caller rather than
        // disappearing into a scheduled block.
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

        func post() {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        if let target, !target.isActive {
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay, execute: post)
            return activationDelay
        }

        post()
        return 0
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
