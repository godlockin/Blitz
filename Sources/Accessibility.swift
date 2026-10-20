import ApplicationServices
import AppKit

enum Accessibility {
    static var trusted: Bool {
        // Prefer options API — more accurate after adhoc re-sign.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func requestPrompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for s in urls {
            if let u = URL(string: s) {
                NSWorkspace.shared.open(u)
                return
            }
        }
    }

    static func frontmostElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success else { return nil }
        return (focused as! AXUIElement)
    }

    static func setFocusedStringValue(_ text: String) -> Bool {
        guard let el = frontmostElement() else { return false }
        let err = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFTypeRef)
        return err == .success
    }

    static func frontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: AnyObject?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window)
        guard err == .success else { return nil }
        return (window as! AXUIElement)
    }

    static func setFrontWindowFrame(_ frame: CGRect) -> Bool {
        guard let win = frontmostWindow() else { return false }
        var pos = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.size.width, height: frame.size.height)
        let posValue = AXValueCreate(.cgPoint, &pos)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        let e1 = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posValue)
        let e2 = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeValue)
        return e1 == .success && e2 == .success
    }
}
