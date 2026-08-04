import AppKit
import ApplicationServices
import Foundation

/// The text field that had keyboard focus when recording started, plus where its
/// caret is on screen. Captured up front because focus moves the moment the user
/// interacts with anything else.
struct FocusedInput {
    /// The focused accessibility element, when it's an editable text control.
    let element: AXUIElement?
    /// The app that owned it — the fallback target for a synthetic ⌘V.
    let application: NSRunningApplication?
    /// Caret rectangle in Cocoa screen coordinates, when the app reports one.
    let caretRect: CGRect?
    /// Human-readable target, e.g. "Safari — text field". Shown in the panel.
    let describedTarget: String?

    var isEditable: Bool { element != nil }

    /// Nothing focused, or no Accessibility permission.
    static var none: FocusedInput {
        FocusedInput(
            element: nil,
            application: NSWorkspace.shared.frontmostApplication,
            caretRect: nil,
            describedTarget: nil
        )
    }

    // MARK: - Capture

    /// Reads the system-wide focused element. Requires Accessibility permission;
    /// without it this degrades to `.none` rather than failing.
    static func capture() -> FocusedInput {
        let app = NSWorkspace.shared.frontmostApplication
        guard Delivery.hasAccessibilityPermission else { return .none }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success else { return .none }

        // CFTypeRef → AXUIElement is a checked cast; a non-element means no target.
        guard CFGetTypeID(focused as CFTypeRef) == AXUIElementGetTypeID() else { return .none }
        let element = focused as! AXUIElement

        guard isEditableTextElement(element) else {
            return FocusedInput(
                element: nil,
                application: app,
                caretRect: nil,
                describedTarget: nil
            )
        }

        return FocusedInput(
            element: element,
            application: app,
            caretRect: caretRect(of: element),
            describedTarget: describe(element, app: app)
        )
    }

    /// An element counts as a target when it looks like a text control *and* its
    /// value is writable — read-only fields shouldn't be pasted into.
    private static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let valueWritable = AXUIElementIsAttributeSettable(
            element, kAXValueAttribute as CFString, &settable
        ) == .success && settable.boolValue

        var selectedTextSettable: DarwinBoolean = false
        let selectionWritable = AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &selectedTextSettable
        ) == .success && selectedTextSettable.boolValue

        // A settable value is the cleanest signal, but plenty of real text fields
        // don't report one — browsers and Electron apps especially. Requiring it
        // classified those as "not a text field" and skipped insertion entirely,
        // which is the common case, not an edge case.
        //
        // A selected-text *range* is the better tell: only text controls have a
        // caret, and web inputs expose it even when they refuse a direct write.
        var range: AnyObject?
        let hasCaret = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &range
        ) == .success

        let role = role(of: element)
        let textRole = [
            "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        ].contains(role)

        // Controls that are definitely not text, whatever else they report.
        switch role {
        case "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem", "AXSlider",
             "AXPopUpButton", "AXImage", "AXLink", "AXDisclosureTriangle":
            return false
        default:
            break
        }

        return valueWritable || selectionWritable || hasCaret || textRole
    }

    private static func role(of element: AXUIElement) -> String {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &value
        ) == .success else { return "" }
        return value as? String ?? ""
    }

    /// Caret position, via the selected range → bounds parameterised attribute.
    /// Many apps don't implement it; callers fall back to the mouse location.
    private static func caretRect(of element: AXUIElement) -> CGRect? {
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let rangeValue else { return nil }

        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &bounds
        ) == .success, let bounds else { return nil }

        var rect = CGRect.zero
        guard CFGetTypeID(bounds as CFTypeRef) == AXValueGetTypeID(),
              AXValueGetValue(bounds as! AXValue, .cgRect, &rect)
        else { return nil }

        // A zero-width caret still has a usable origin; a fully empty rect doesn't.
        guard rect.origin != .zero || rect.height > 0 else { return nil }
        return flipToCocoa(rect)
    }

    /// Accessibility reports screen coordinates with the origin at the top-left of
    /// the primary display; Cocoa's origin is bottom-left.
    private static func flipToCocoa(_ rect: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(
            x: rect.origin.x,
            y: primary.frame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func describe(_ element: AXUIElement, app: NSRunningApplication?) -> String {
        let appName = app?.localizedName ?? "the frontmost app"
        switch role(of: element) {
        case "AXTextField": return "\(appName) — text field"
        case "AXTextArea": return "\(appName) — text area"
        case "AXSearchField": return "\(appName) — search field"
        case "AXComboBox": return "\(appName) — combo box"
        default: return appName
        }
    }
}
