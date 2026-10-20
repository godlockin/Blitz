import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, SettingsWindowDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private let panelController = PanelController()
    private let clipboardStore = ClipboardStore.shared
    private lazy var settingsController = SettingsWindowController()
    private lazy var snippetEditor = SnippetEditorWindowController()
    private lazy var catalogEditor = CatalogEditorWindowController()
    private let hotKeys = HotKeyManager.shared
    private var historySubmenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        SnippetStore.shared.load()
        QuicklinkStore.shared.load()
        ScriptCommandStore.shared.load()
        clipboardStore.start()
        clipboardStore.onHistoryChanged = { [weak self] in
            DispatchQueue.main.async { self?.refreshStatusMenu() }
        }
        setupStatusItem()
        settingsController.settingsDelegate = self
        SearchService.openSettingsHandler = { [weak self] in
            self?.openSettings()
        }
        panelController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        hotKeys.onAction = { [weak self] action in
            switch action {
            case .launcher:
                self?.showPanel()
            case .clipboard:
                self?.showClipboardHistory()
            case .snippets:
                self?.showSnippetsMenu()
            case .historyPopup:
                self?.popHistoryMenuAtMouse()
            case .mainMenu:
                self?.popMainMenuAtMouse()
            case .settings:
                self?.openSettings()
            case .clearHistory:
                self?.clearClipboard()
            case .editSnippets:
                self?.openSnippetEditor()
            }
        }
        hotKeys.onSnippetFolder = { [weak self] folderId in
            self?.popSnippetFolderMenu(folderId)
        }
        migrateAwayFromRaycastHotkeyIfNeeded()
        resolveHotKeyConflicts()
        registerHotKey(showAlertOnFailure: false)
        FileLogger.log(hotKeys.statusMessage)
        remindAccessibilityIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(forceShowPanel),
            name: .blitzShowPanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .blitzOpenSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSnippetEditor),
            name: .blitzOpenSnippets,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showClipboardHistory),
            name: .blitzShowClipboard,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openCatalogEditor(_:)),
            name: .blitzOpenCatalogs,
            object: nil
        )

        let store = SettingsStore.shared
        if store.showWelcomeOnLaunch && !store.didOpenSettingsOnce {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openSettings()
            }
        } else if hotKeys.lastStatus != noErr || hotKeys.statusMessage.contains("switched") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.notifyHotKeyStatus()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregister()
        clipboardStore.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        panelController.show()
    }

    private func migrateAwayFromRaycastHotkeyIfNeeded() {
        let store = SettingsStore.shared
        let isOptionSpace =
            store.hotKeyCode == UInt32(kVK_Space) &&
            store.hotKeyModifiers == UInt32(optionKey)
        if isOptionSpace {
            store.resetHotKeyToDefault()
            NSLog("Blitz: migrated hotkey Option+Space → Control+Option+Space")
        }
    }

    /// If Main menu and Clipboard panel share the same chord, move Main to ⌥⌘V.
    private func resolveHotKeyConflicts() {
        let store = SettingsStore.shared
        let same =
            store.mainMenuHotKeyCode == store.clipboardHotKeyCode &&
            store.mainMenuHotKeyModifiers == store.clipboardHotKeyModifiers
        if same {
            store.mainMenuHotKeyCode = UInt32(kVK_ANSI_V)
            store.mainMenuHotKeyModifiers = UInt32(optionKey | cmdKey)
            FileLogger.log("hotkey: Main collided with Clipboard — remapped Main to ⌥⌘V")
        }
    }

    private func setupMainMenu() {
        let main = NSMenu()
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Blitz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        applyStatusItemVisibility()
    }

    private func applyStatusItemVisibility() {
        if !SettingsStore.shared.showStatusItem {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "Blitz"
            item.button?.toolTip = "Blitz — left: history · right: menu"
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        }
        if let item = statusItem {
            rebuildMenu(for: item)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popStatusMenu()
            return
        }
        // Left click: pop Clipy-style history menu
        popHistoryMenu()
    }

    private func popStatusMenu() {
        guard let menu = statusMenu, let button = statusItem?.button else { return }
        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    private func popHistoryMenu() {
        let menu = NSMenu()
        ClipboardMenuController.populateHistory(
            into: menu,
            target: self,
            action: #selector(historyMenuItemClicked(_:))
        )
        menu.addItem(withTitle: "Clipboard Panel…", action: #selector(showClipboardHistory), keyEquivalent: "")
        if let button = statusItem?.button {
            let point = NSPoint(x: 0, y: button.bounds.height + 2)
            menu.popUp(positioning: nil, at: point, in: button)
        } else {
            ClipboardMenuController.popUpAtMouse(menu)
        }
    }

    private func popHistoryMenuAtMouse() {
        PasteHelper.captureFrontApp()
        let menu = NSMenu()
        ClipboardMenuController.populateHistory(
            into: menu,
            target: self,
            action: #selector(historyMenuItemClicked(_:))
        )
        ClipboardMenuController.popUpAtMouse(menu)
    }

    private func popMainMenuAtMouse() {
        PasteHelper.captureFrontApp()
        let menu = NSMenu()
        ClipboardMenuController.populateMain(
            into: menu,
            target: self,
            historyAction: #selector(historyMenuItemClicked(_:)),
            snippetAction: #selector(snippetMenuItemClicked(_:))
        )
        ClipboardMenuController.popUpAtMouse(menu)
    }

    @objc private func showSnippetsMenu() {
        PasteHelper.captureFrontApp()
        let menu = NSMenu()
        ClipboardMenuController.populateSnippets(
            into: menu,
            target: self,
            action: #selector(snippetMenuItemClicked(_:))
        )
        if let button = statusItem?.button {
            let point = NSPoint(x: 0, y: button.bounds.height + 2)
            menu.popUp(positioning: nil, at: point, in: button)
        } else {
            ClipboardMenuController.popUpAtMouse(menu)
        }
    }

    private func popSnippetFolderMenu(_ folderId: String) {
        PasteHelper.captureFrontApp()
        guard let folder = SnippetStore.shared.folders.first(where: { $0.id == folderId }) else { return }
        let menu = NSMenu(title: folder.name)
        let label = NSMenuItem(title: folder.name, action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)
        for s in folder.snippets where s.enabled {
            let title = s.keyword.isEmpty ? oneLine(s.content) : "\(s.keyword) — \(oneLine(s.content))"
            let mi = NSMenuItem(title: title, action: #selector(snippetMenuItemClicked(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = s.id
            menu.addItem(mi)
        }
        ClipboardMenuController.popUpAtMouse(menu)
    }

    private func oneLine(_ s: String) -> String {
        let p = s.replacingOccurrences(of: "\n", with: " ")
        return p.count > 40 ? String(p.prefix(40)) + "…" : p
    }

    @objc private func historyMenuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ClipboardMenuController.handleSelection(id: id)
    }

    @objc private func snippetMenuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let snippet = SnippetStore.shared.allEnabledSnippets.first(where: { $0.id == id }) else { return }
        PasteHelper.captureFrontApp()
        SnippetStore.shared.pasteSnippet(snippet)
    }

    private func rebuildMenu(for item: NSStatusItem) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Blitz", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Clipboard Panel", action: #selector(showClipboardHistory), keyEquivalent: "")
        menu.addItem(withTitle: "Edit Snippets…", action: #selector(openSnippetEditor), keyEquivalent: "")
        menu.addItem(withTitle: "Edit Quicklinks & Scripts…", action: #selector(openCatalogFromMenu), keyEquivalent: "")

        let history = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        ClipboardMenuController.populateHistory(
            into: sub,
            target: self,
            action: #selector(historyMenuItemClicked(_:))
        )
        history.submenu = sub
        historySubmenu = sub
        menu.addItem(history)

        menu.addItem(NSMenuItem.separator())
        let hk = NSMenuItem(
            title: SettingsStore.shared.hotKeyDisplayString + " / "
                + SettingsStore.shared.clipboardHotKeyDisplayString + " / "
                + SettingsStore.shared.snippetsHotKeyDisplayString,
            action: nil,
            keyEquivalent: ""
        )
        hk.isEnabled = false
        menu.addItem(hk)

        if !hotKeys.statusMessage.isEmpty {
            let note = NSMenuItem(title: hotKeys.statusMessage, action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)

        let axTitle = Accessibility.trusted
            ? "Accessibility: OK"
            : "Enable Accessibility (required for paste)…"
        menu.addItem(withTitle: axTitle, action: #selector(requestAccessibility), keyEquivalent: "")

        let login = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Clear Clipboard History", action: #selector(clearClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Blitz", action: #selector(quit), keyEquivalent: "q")
        statusMenu = menu
        item.menu = nil
    }

    private func refreshStatusMenu() {
        guard let item = statusItem else { return }
        rebuildMenu(for: item)
    }

    private func registerHotKey(showAlertOnFailure: Bool) {
        let ok = hotKeys.register(autoFallback: true)
        refreshStatusMenu()
        if showAlertOnFailure || settingsController.window?.isVisible == true {
            settingsController.reloadFromStore()
            settingsController.updateHotKeyStatus(hotKeys.statusMessage)
        }

        if !ok && showAlertOnFailure {
            notifyHotKeyStatus()
        }
    }

    private func notifyHotKeyStatus() {
        let alert = NSAlert()
        alert.messageText = "Blitz hotkey"
        alert.informativeText = hotKeys.statusMessage.isEmpty
            ? "Could not register the global hotkey. Open Settings and pick another shortcut."
            : hotKeys.statusMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            openSettings()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func settingsDidChangeHotKey() {
        registerHotKey(showAlertOnFailure: true)
    }

    func settingsDidChangePanelSize() {
        panelController.applyPanelSize()
    }

    func settingsDidChangeClipboardPrefs() {
        clipboardStore.applyMaxItems(SettingsStore.shared.clipboardMaxItems)
        clipboardStore.reschedulePeriodicCleanup()
        ScreenshotObserver.shared.restart()
        applyStatusItemVisibility()
        refreshStatusMenu()
        registerHotKey(showAlertOnFailure: false)
    }

    @objc func showPanel() {
        panelController.toggle(mode: .launcher)
    }

    @objc func forceShowPanel() {
        panelController.show(mode: .launcher)
    }

    @objc func showClipboardHistory() {
        panelController.toggle(mode: .clipboard)
    }

    @objc func openSnippetEditor() {
        panelController.hide()
        snippetEditor.showEditor()
    }

    @objc func openCatalogFromMenu() {
        panelController.hide()
        catalogEditor.showEditor(preferScripts: false)
    }

    @objc func openCatalogEditor(_ note: Notification) {
        panelController.hide()
        let scripts = (note.userInfo?["scripts"] as? Bool) ?? false
        catalogEditor.showEditor(preferScripts: scripts)
    }

    @objc func openSettings() {
        panelController.hide()
        settingsController.show()
        settingsController.updateHotKeyStatus(hotKeys.statusMessage)
        refreshStatusMenu()
    }

    @objc func requestAccessibility() {
        Accessibility.requestPrompt()
        Accessibility.openSystemSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.registerHotKey(showAlertOnFailure: false)
            self?.refreshStatusMenu()
        }
    }

    private func remindAccessibilityIfNeeded() {
        guard !Accessibility.trusted else {
            FileLogger.log("Accessibility: trusted")
            statusItem?.button?.title = "Blitz"
            return
        }
        FileLogger.log("Accessibility: NOT trusted — paste will beep until enabled")
        statusItem?.button?.title = "Blitz!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let alert = NSAlert()
            alert.messageText = "Blitz needs Accessibility"
            alert.informativeText = "Without it, clipboard paste cannot reach the cursor (you’ll hear a beep).\n\nSystem Settings → Privacy & Security → Accessibility → enable Blitz.\n\nSigned builds with the “Blitz Dev” identity keep this permission across rebuilds."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let r = alert.runModal()
            if r == .alertFirstButtonReturn {
                Accessibility.requestPrompt()
                Accessibility.openSystemSettings()
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.isEnabled.toggle()
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
        settingsController.reloadFromStore()
    }

    @objc func clearClipboard() {
        ClipboardStore.shared.clear(confirm: true)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
