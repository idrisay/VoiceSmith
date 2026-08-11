import AppKit
import Carbon.HIToolbox
import Foundation

/// Carbon hot-key registration. Chosen over an event tap because it needs no
/// Accessibility permission — the app stays usable for clipboard-only workflows
/// even when the user declines that prompt.
final class GlobalShortcut {
    /// The record/stop shortcut the user configures.
    static let shared = GlobalShortcut(id: 1)
    /// Bare Escape, registered only while recording. It has to be a system hot key
    /// rather than a local event monitor: the recording panel never activates the
    /// app, so a local monitor would never see the key press.
    static let cancel = GlobalShortcut(id: 2)

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onFire: (() -> Void)?

    private init(id: UInt32) {
        self.id = id
    }

    /// Returns false when the combination couldn't be claimed — normally because
    /// macOS or another app already owns it. The caller surfaces that rather than
    /// leaving the user with a shortcut that silently does someone else's thing.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        unregister()
        onFire = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Without a handler the hot key still registers and still fires — into
        // nothing. Reported as a failure so Settings says the shortcut is dead
        // rather than leaving the user pressing a key that does nothing.
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return noErr }
                let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.id == shortcut.id else { return noErr }

                DispatchQueue.main.async { shortcut.onFire?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x5653_4D54), id: id) // 'VSMT'
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard installed == noErr, status == noErr, hotKeyRef != nil else {
            // Don't sit on a combination we can't service — another app may be
            // able to use it, and we'd only be swallowing the keystroke.
            unregister()
            return false
        }
        return true
    }

    /// Combinations macOS reserves for itself. Registering one appears to succeed
    /// but the system handler runs first, so the user presses the shortcut and
    /// gets Spotlight or a Finder window instead of VoiceSmith.
    ///
    /// `⌥⌘Space` — the obvious choice, and VoiceSmith's original default — is
    /// "Show Finder search window", which is exactly why it yanked users to the
    /// desktop on every press.
    static func systemConflict(keyCode: UInt32, modifiers: UInt32) -> String? {
        let cmd = UInt32(cmdKey), opt = UInt32(optionKey), ctrl = UInt32(controlKey)
        let shift = UInt32(shiftKey)

        switch (Int(keyCode), modifiers) {
        case (kVK_Space, cmd):
            return "Spotlight search"
        case (kVK_Space, opt | cmd):
            return "Show Finder search window"
        case (kVK_Space, ctrl | cmd):
            return "Emoji & Symbols"
        case (kVK_Space, ctrl):
            return "Select the previous input source"
        case (kVK_Space, ctrl | opt):
            return "Select the next input source"
        case (kVK_Space, shift | cmd):
            return "Spotlight (Finder search) on some layouts"
        case (kVK_ANSI_D, opt | cmd):
            return "Show or hide the Dock"
        case (kVK_Tab, cmd), (kVK_Tab, shift | cmd):
            return "Application switcher"
        case (kVK_Escape, opt | cmd):
            return "Force Quit"
        case (kVK_ANSI_Q, shift | cmd):
            return "Log out"
        default:
            return nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    /// Human-readable form of a Carbon key code + modifier mask, for Settings.
    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "Tab"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_V: return "V"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        default: return "Key \(keyCode)"
        }
    }

    /// Converts AppKit modifier flags into the Carbon mask `RegisterEventHotKey` wants.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}
