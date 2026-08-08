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
final class DoubleTapShortcut {
    /// Double-tap Shift: start or stop dictating.
    static let shift = DoubleTapShortcut(modifier: .shift)
    /// Double-tap Option: capture straight to the to-do list.
    ///
    /// Option rather than Control: macOS offers "Press Control Twice" as a
    /// Dictation shortcut, and two dictation triggers on one chord would be a
    /// uniquely bad collision. Option has no system meaning when tapped alone.
    static let option = DoubleTapShortcut(modifier: .option)

    static var all: [DoubleTapShortcut] { [.shift, .option] }

    let modifier: NSEvent.ModifierFlags

    /// Two taps must land within this window. Matches the feel of other
    /// double-tap-Shift affordances; long enough to be comfortable, short enough
    /// that deliberate separate Shift presses don't run together.
    var threshold: TimeInterval = 0.35

    private var monitors: [Any] = []
    private var onFire: (() -> Void)?

    private var modifierIsDown = false
    private var lastTapAt: Date?

    private init(modifier: NSEvent.ModifierFlags) {
        self.modifier = modifier
    }

    var isEnabled: Bool { !monitors.isEmpty }

    /// Returns false when Accessibility hasn't been granted, since global
    /// monitors receive nothing without it.
    @discardableResult
    func enable(action: @escaping () -> Void) -> Bool {
        disable()
        guard AXIsProcessTrusted() else { return false }
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
        modifierIsDown = false
        lastTapAt = nil
    }

    /// Forget a pending first tap. Called when another modifier fires so that
    /// Shift-then-Option doesn't read as a double-tap of either.
    func resetPendingTap() {
        lastTapAt = nil
    }

    private func handleFlags(_ event: NSEvent) {
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
