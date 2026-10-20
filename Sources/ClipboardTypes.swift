import AppKit
import Foundation

enum ClipboardKind: String, Codable, CaseIterable {
    case text
    case image
    case rtf
    case html
    case pdf
    case file
    case url
    case color
}

/// Which pasteboard flavors Blitz may store (Clipy-style toggles).
struct PasteboardTypeSettings: Codable, Equatable {
    var string = true
    var rtf = true
    var html = true
    var pdf = true
    var filenames = true
    var url = true
    var tiff = true

    static let `default` = PasteboardTypeSettings()
}

enum ModifierActionKey: Int, Codable, CaseIterable {
    case command = 0
    case shift = 1
    case control = 2
    case option = 3

    var displayName: String {
        switch self {
        case .command: return "⌘"
        case .shift: return "⇧"
        case .control: return "⌃"
        case .option: return "⌥"
        }
    }

    func isPressed(in flags: NSEvent.ModifierFlags = NSEvent.modifierFlags) -> Bool {
        switch self {
        case .command: return flags.contains(.command)
        case .shift: return flags.contains(.shift)
        case .control: return flags.contains(.control)
        case .option: return flags.contains(.option)
        }
    }
}

enum HistoryClearInterval: Int, Codable, CaseIterable {
    case hour = 3600
    case day = 86_400
    case week = 604_800
    case month = 2_592_000

    var title: String {
        switch self {
        case .hour: return "Every hour"
        case .day: return "Every day"
        case .week: return "Every week"
        case .month: return "Every month"
        }
    }
}

enum ColorParse {
    /// Returns (#RRGGBB, NSColor) when text looks like a color.
    static func parse(_ text: String) -> (hex: String, color: NSColor)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 32, let hex = normalizeHex(t) {
            if let c = color(fromHex: hex) { return (hex, c) }
        }
        // rgb( r, g, b ) / rgba(...)
        let lower = t.lowercased()
        if lower.hasPrefix("rgb") {
            let nums = lower.compactMap { $0.isNumber || $0 == "." || $0 == "," ? $0 : nil }
            let parts = String(nums).split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 3 {
                let r = parts[0] > 1 ? parts[0] / 255 : parts[0]
                let g = parts[1] > 1 ? parts[1] / 255 : parts[1]
                let b = parts[2] > 1 ? parts[2] / 255 : parts[2]
                let c = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
                let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
                return (hex, c)
            }
        }
        return nil
    }

    private static func normalizeHex(_ s: String) -> String? {
        var t = s
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 {
            t = t.map { "\($0)\($0)" }.joined()
        }
        guard t.count == 6, t.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + t.uppercased()
    }

    private static func color(fromHex hex: String) -> NSColor? {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }

    static func swatchImage(_ color: NSColor, size: CGFloat = 14) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 3, yRadius: 3).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1), xRadius: 3, yRadius: 3).stroke()
        img.unlockFocus()
        return img
    }
}
