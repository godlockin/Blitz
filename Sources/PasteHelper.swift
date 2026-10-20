import AppKit
import ApplicationServices
import Carbon

/// Remembers the app (and focused AX element) before Blitz opened, then pastes at the caret.
///
/// Electron (Cursor / VS Code / WeChat) often reports AX `SelectedText` success without
/// inserting. We restore focus, then paste via Edit→Paste / CGEvent ⌘V / System Events.
enum PasteHelper {
    private static var previousApp: NSRunningApplication?
    private static var previousPID: pid_t = 0
    private static var previousFocused: AXUIElement?

    static func captureFrontApp() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        previousFocused = nil

        let front: NSRunningApplication? = {
            if let f = NSWorkspace.shared.frontmostApplication,
               f.processIdentifier != selfPID { return f }
            return NSWorkspace.shared.runningApplications.first(where: {
                $0.activationPolicy == .regular &&
                $0.processIdentifier != selfPID &&
                $0.isActive
            })
        }()

        guard let front else { return }
        previousApp = front
        previousPID = front.processIdentifier

        let appEl = AXUIElementCreateApplication(previousPID)
        var focused: AnyObject?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused) == .success {
            previousFocused = (focused as! AXUIElement)
        }

        FileLogger.log("paste: captured front \(front.localizedName ?? "?") pid=\(previousPID) focused=\(previousFocused != nil)")
    }

    static func pasteClipboardItem(id: String, plainText: Bool = false) {
        guard let item = ClipboardStore.shared.items.first(where: { $0.id == id }) else {
            FileLogger.log("paste: missing item \(id)")
            return
        }

        if !Accessibility.trusted {
            FileLogger.log("paste: blocked — Accessibility not trusted (would beep)")
            Accessibility.requestPrompt()
            Accessibility.openSystemSettings()
            return
        }

        ClipboardStore.shared.suppressNextCapture(for: 2.0)
        ClipboardStore.shared.writeToPasteboard(item, plainText: plainText)

        guard SettingsStore.shared.pasteAutomatically else {
            FileLogger.log("paste: copy-only (pasteAutomatically=false) \(item.kind)")
            return
        }

        let electron = isElectronLikeTarget()
        let targetName = resolveTarget()?.localizedName ?? "?"

        DispatchQueue.main.async {
            if #available(macOS 14.0, *), let app = resolveTarget() {
                NSApp.yieldActivation(to: app)
            }
            for w in NSApp.windows { w.orderOut(nil) }
            NSApp.hide(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                activatePreviousApp()
                restoreFocus()

                let settle: TimeInterval = electron ? 0.45 : 0.28
                DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                    // Ensure target is still frontmost after settle.
                    activatePreviousApp()
                    restoreFocus()
                    releaseStuckModifiers()
                    ClipboardStore.shared.writeToPasteboard(item, plainText: plainText)

                    // Prefer menu Paste (works when keystroke is swallowed by Electron).
                    if clickEditPasteMenu() {
                        FileLogger.log("paste: Edit→Paste → \(targetName) electron=\(electron)")
                        return
                    }

                    postCommandV()
                    FileLogger.log("paste: CGEvent ⌘V → \(targetName) electron=\(electron)")

                    // Backup keystroke after a beat if menu + CGEvent race focus.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        _ = keystrokeCommandVViaSystemEvents(processName: targetName)
                        FileLogger.log("paste: System Events ⌘V backup → \(targetName)")
                    }
                }
            }
        }
    }

    private static func isElectronLikeTarget() -> Bool {
        guard let app = resolveTarget() else { return false }
        let name = (app.localizedName ?? "").lowercased()
        let bid = (app.bundleIdentifier ?? "").lowercased()
        let hints = [
            "cursor", "code", "visual studio", "electron",
            "chrome", "edge", "chromium", "brave", "arc",
            "slack", "discord", "figma", "notion", "obsidian",
            "wechat", "微信", "telegram", "typora", "zed"
        ]
        if hints.contains(where: { name.contains($0) || bid.contains($0) }) {
            return true
        }
        if let url = app.bundleURL {
            let frameworks = url.appendingPathComponent("Contents/Frameworks")
            if let items = try? FileManager.default.contentsOfDirectory(atPath: frameworks.path) {
                if items.contains(where: { $0.localizedCaseInsensitiveContains("Electron") }) {
                    return true
                }
            }
        }
        return false
    }

    /// Paste arbitrary text without adding a history entry (snippets).
    static func pasteTextDirect(_ text: String) {
        if !Accessibility.trusted {
            Accessibility.requestPrompt()
            Accessibility.openSystemSettings()
            return
        }
        ClipboardStore.shared.suppressNextCapture(for: 2.0)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardStore.shared.notePasteboardWritten()

        DispatchQueue.main.async {
            for w in NSApp.windows { w.orderOut(nil) }
            NSApp.hide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                activatePreviousApp()
                restoreFocus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    releaseStuckModifiers()
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    if clickEditPasteMenu() {
                        FileLogger.log("paste: snippet Edit→Paste")
                    } else {
                        postCommandV()
                        FileLogger.log("paste: snippet CGEvent ⌘V")
                    }
                }
            }
        }
    }

    private static func resolveTarget() -> NSRunningApplication? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if previousPID != 0,
           let match = NSWorkspace.shared.runningApplications.first(where: {
               $0.processIdentifier == previousPID && !$0.isTerminated
           }) {
            return match
        }
        if let app = previousApp, app.processIdentifier != selfPID, !app.isTerminated {
            return app
        }
        return nil
    }

    private static func activatePreviousApp() {
        guard let app = resolveTarget() else {
            FileLogger.log("paste: no previous app")
            return
        }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: app)
            _ = app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        let pid = app.processIdentifier
        let name = app.localizedName ?? ""
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if !name.isEmpty {
            script = """
            tell application "System Events"
              set frontmost of process "\(escaped)" to true
            end tell
            """
        } else {
            script = """
            tell application "System Events"
              set frontmost of first process whose unix id is \(pid) to true
            end tell
            """
        }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { FileLogger.log("paste: activate script \(error)") }
        FileLogger.log("paste: activated \(name) pid=\(pid)")
    }

    private static func restoreFocus() {
        guard let focused = previousFocused, previousPID != 0 else { return }
        let appEl = AXUIElementCreateApplication(previousPID)
        // Raise the app window first, then put keyboard focus back.
        var window: AnyObject?
        if AXUIElementCopyAttributeValue(focused, kAXWindowAttribute as CFString, &window) == .success,
           let win = window {
            AXUIElementPerformAction(win as! AXUIElement, kAXRaiseAction as CFString)
        }
        AXUIElementSetAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, focused)
        AXUIElementSetAttributeValue(focused, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// Click Edit → Paste in the target app's menu bar (often more reliable than ⌘V on Electron).
    @discardableResult
    private static func clickEditPasteMenu() -> Bool {
        guard previousPID != 0 else { return false }
        let appEl = AXUIElementCreateApplication(previousPID)

        var menuBarObj: AnyObject?
        guard AXUIElementCopyAttributeValue(appEl, kAXMenuBarAttribute as CFString, &menuBarObj) == .success,
              let menuBar = menuBarObj else { return false }

        var menusObj: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &menusObj) == .success,
              let menus = menusObj as? [AXUIElement] else { return false }

        for menu in menus {
            var titleObj: AnyObject?
            AXUIElementCopyAttributeValue(menu, kAXTitleAttribute as CFString, &titleObj)
            let title = (titleObj as? String) ?? ""
            // English "Edit" / Chinese "编辑"
            guard title == "Edit" || title == "编辑" || title.lowercased() == "edit" else { continue }

            var itemsObj: AnyObject?
            // Menu bar item → menu → children
            guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &itemsObj) == .success,
                  let firstLevel = itemsObj as? [AXUIElement], let submenu = firstLevel.first else { continue }

            var pasteItemsObj: AnyObject?
            guard AXUIElementCopyAttributeValue(submenu, kAXChildrenAttribute as CFString, &pasteItemsObj) == .success,
                  let items = pasteItemsObj as? [AXUIElement] else { continue }

            for item in items {
                var itemTitleObj: AnyObject?
                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &itemTitleObj)
                let itemTitle = (itemTitleObj as? String) ?? ""
                if itemTitle.hasPrefix("Paste") || itemTitle.hasPrefix("粘贴") || itemTitle == "Paste" {
                    let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    if err == .success { return true }
                }
            }
        }
        return false
    }

    @discardableResult
    private static func keystrokeCommandVViaSystemEvents(processName: String) -> Bool {
        let escaped = processName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        if processName != "?", !processName.isEmpty {
            script = """
            tell application "System Events"
              tell process "\(escaped)"
                set frontmost to true
                key code 9 using {command down}
              end tell
            end tell
            """
        } else {
            script = """
            tell application "System Events"
              key code 9 using {command down}
            end tell
            """
        }

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        appleScript.executeAndReturnError(&error)
        if let error {
            FileLogger.log("paste: System Events failed \(error)")
            var err2: NSDictionary?
            let fallback = """
            tell application "System Events"
              key code 9 using {command down}
            end tell
            """
            NSAppleScript(source: fallback)?.executeAndReturnError(&err2)
            if let err2 {
                FileLogger.log("paste: System Events fallback failed \(err2)")
                return false
            }
        }
        return true
    }

    private static func releaseStuckModifiers() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keys: [CGKeyCode] = [55, 54, 56, 60, 58, 61, 59, 62]
        for key in keys {
            if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
                up.flags = []
                up.post(tap: .cghidEventTap)
            }
        }
    }

    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
