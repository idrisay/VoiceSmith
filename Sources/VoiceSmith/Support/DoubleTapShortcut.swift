import AppKit
import Foundation

/// Detects a double-tap of Shift anywhere in the system.
///
/// This can't be a Carbon hot key: `RegisterEventHotKey` needs a real key plus
/// modifiers, and has no concept of tapping a modifier twice. So it watches
/// `flagsChanged` instead — which means it needs Accessibility permission, and
/// degrades to "off" without it rather than failing silently.
final class DoubleTapShortcut {
    static let shared = DoubleTapShortcut()

    /// Two taps must land within this window. Matches the feel of other
    /// double-tap-Shift affordances; long enough to be comfortable, short enough
    /// that deliberate separate Shift presses don't run together.
    var threshold: TimeInterval = 0.35

    private var monitors: [Any] = []
    private var onFire: (() -> Void)?

    private var shiftIsDown = false
    private var lastTapAt: Date?

    private init() {}

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
        shiftIsDown = false
        lastTapAt = nil
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shiftAlone = flags == .shift

        if shiftAlone {
            // Rising edge only — holding Shift down must not repeat.
            guard !shiftIsDown else { return }
            shiftIsDown = true

            let now = Date()
            if let last = lastTapAt, now.timeIntervalSince(last) <= threshold {
                lastTapAt = nil
                shiftIsDown = true
                onFire?()
            } else {
                lastTapAt = now
            }
            return
        }

        if flags.isEmpty {
            shiftIsDown = false
            return
        }

        // Shift combined with anything else is a normal chord, not our trigger.
        shiftIsDown = flags.contains(.shift)
        lastTapAt = nil
    }
}
