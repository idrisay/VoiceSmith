import AppKit
import Foundation

/// Detects a double-tap of one modifier key anywhere in the system.
///
/// This can't be a Carbon hot key: `RegisterEventHotKey` needs a real key plus
/// modifiers, and has no concept of tapping a modifier twice. So it watches
/// `flagsChanged` instead — which means it needs Accessibility permission, and
/// degrades to "off" without it rather than failing silently.
///
/// One instance per modifier, each watching independently. They can't be folded
/// into a single monitor: a tap of one modifier has to *reset* the other's
/// pending state, or alternating Shift and Option quickly would fire both.
/// Which modifier a double-tap trigger listens to.
///
/// Suggested rather than imposed: the defaults below are the ones least likely
/// to collide, but every Mac has a different set of apps competing for the same
/// taps, so all of them are offered and any of them can be switched off.
enum TapModifier: String, CaseIterable, Identifiable, Codable {
    case off, shift, control, option, command

    var id: String { rawValue }

    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .off:      return nil
        case .shift:    return .shift
        case .control:  return .control
        case .option:   return .option
        case .command:  return .command
        }
    }

    /// For pickers.
    var displayName: String {
        switch self {
        case .off:      return "Off"
        case .shift:    return "Double-tap ⇧ Shift"
        case .control:  return "Double-tap ⌃ Control"
        case .option:   return "Double-tap ⌥ Option"
        case .command:  return "Double-tap ⌘ Command"
        }
    }

    /// For running text: "double-tap ⇧".
    var shortLabel: String {
        switch self {
        case .off:      return "off"
        case .shift:    return "double-tap ⇧"
        case .control:  return "double-tap ⌃"
        case .option:   return "double-tap ⌥"
        case .command:  return "double-tap ⌘"
        }
    }

    /// What else is likely to want the same tap. Shown next to the choice
    /// rather than hidden in documentation, because the user is picking right
    /// then and this is what they need to decide with.
    var caution: String? {
        switch self {
        case .control:
            return "macOS offers \"Press Control Twice\" as its own Dictation shortcut. If that's on, both will fire."
        case .shift:
            return "JetBrains IDEs use double-tap Shift for Search Everywhere. In those apps both will fire."
        case .command:
            return "Some launchers use double-tap Command. Check yours before relying on it."
        case .option, .off:
            return nil
        }
    }
}

final class DoubleTapShortcut {
    /// Start or stop dictating. Suggested: Shift.
    static let dictation = DoubleTapShortcut()
    /// Capture straight to the to-do list. Suggested: Option — it is the only
    /// one of the four with no established meaning when tapped alone.
    static let todo = DoubleTapShortcut()

    static var all: [DoubleTapShortcut] { [.dictation, .todo] }

    /// Nil until enabled. Assignable, because the user chooses it.
    private(set) var modifier: NSEvent.ModifierFlags?

    /// Two taps must land within this window. Matches the feel of other
    /// double-tap-Shift affordances; long enough to be comfortable, short enough
    /// that deliberate separate Shift presses don't run together.
    var threshold: TimeInterval = 0.35

    private var monitors: [Any] = []
    private var onFire: (() -> Void)?

    private var modifierIsDown = false
    private var lastTapAt: Date?

    private init() {}

    var isEnabled: Bool { !monitors.isEmpty }

    /// Returns false when Accessibility hasn't been granted, since global
    /// monitors receive nothing without it.
    @discardableResult
    func enable(modifier: NSEvent.ModifierFlags, action: @escaping () -> Void) -> Bool {
        disable()
        guard AXIsProcessTrusted() else { return false }
        self.modifier = modifier
        onFire = action

        // Global monitors see other apps; local monitors see our own windows.
        // Both are needed for the shortcut to work everywhere.
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged],
            handler: { [weak self] event in self?.handleFlags(event) }
        ) {
            monitors.append(global)
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event)
            return event
        } as Any)

        // Any real keystroke between the taps means the user is typing, not
        // triggering — most obviously when shifting for capital letters.
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown],
            handler: { [weak self] _ in self?.lastTapAt = nil }
        ) {
            monitors.append(global)
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.lastTapAt = nil
            return event
        } as Any)

        return true
    }

    func disable() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        onFire = nil
        modifier = nil
        modifierIsDown = false
        lastTapAt = nil
    }

    /// Forget a pending first tap. Called when another modifier fires so that
    /// Shift-then-Option doesn't read as a double-tap of either.
    func resetPendingTap() {
        lastTapAt = nil
    }

    private func handleFlags(_ event: NSEvent) {
        guard let modifier else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let aloneNow = flags == modifier

        if aloneNow {
            // Rising edge only — holding the key down must not repeat.
            guard !modifierIsDown else { return }
            modifierIsDown = true

            // A tap of this modifier invalidates any half-finished tap of the
            // other one, so alternating them can never complete a pair.
            for other in Self.all where other !== self { other.resetPendingTap() }

            let now = Date()
            if let last = lastTapAt, now.timeIntervalSince(last) <= threshold {
                lastTapAt = nil
                modifierIsDown = true
                onFire?()
            } else {
                lastTapAt = now
            }
            return
        }

        if flags.isEmpty {
            modifierIsDown = false
            return
        }

        // Combined with anything else it's a normal chord, not our trigger.
        modifierIsDown = flags.contains(modifier)
        lastTapAt = nil
    }
}
