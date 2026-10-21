import AppKit
import Carbon

protocol SettingsWindowDelegate: AnyObject {
    func settingsDidChangeHotKey()
    func settingsDidChangePanelSize()
    func settingsDidChangeClipboardPrefs()
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    weak var settingsDelegate: SettingsWindowDelegate?

    private let store = SettingsStore.shared
    private var recordingHotKey = false
    private var recordingTarget: RecordingTarget = .launcher
    private enum RecordingTarget { case launcher, clipboard, snippets, mainMenu }

    private let hotKeyField = NSTextField(string: "")
    private let clipboardHotKeyField = NSTextField(string: "")
    private let snippetsHotKeyField = NSTextField(string: "")
    private let mainMenuHotKeyField = NSTextField(string: "")
    private let hotKeyHint = NSTextField(labelWithString: "")
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let welcomeCheckbox = NSButton(checkboxWithTitle: "Show welcome tip on launch", target: nil, action: nil)
    private let iCloudSyncCheckbox = NSButton(checkboxWithTitle: "Sync catalogs via iCloud Drive", target: nil, action: nil)
    private let iCloudClipboardCheckbox = NSButton(checkboxWithTitle: "Also sync text clip index (no images)", target: nil, action: nil)
    private let iCloudStatusLabel = NSTextField(labelWithString: "")
    private let clipboardStepper = NSStepper()
    private let clipboardField = NSTextField(string: "")
    private let fileLimitStepper = NSStepper()
    private let fileLimitField = NSTextField(string: "")
    private let widthField = NSTextField(string: "")
    private let heightField = NSTextField(string: "")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton(title: "Record…", target: nil, action: nil)
    private var keyMonitor: Any?

    // Clipboard parity
    private var typeChecks: [NSButton] = []
    private let ignoreConcealed = NSButton(checkboxWithTitle: "Ignore concealed (password managers)", target: nil, action: nil)
    private let ignoreUniversal = NSButton(checkboxWithTitle: "Ignore Universal Clipboard", target: nil, action: nil)
    private let overwriteSame = NSButton(checkboxWithTitle: "Overwrite same history item", target: nil, action: nil)
    private let copySame = NSButton(checkboxWithTitle: "Allow duplicate copies", target: nil, action: nil)
    private let reorderAfterPaste = NSButton(checkboxWithTitle: "Reorder item to top after paste", target: nil, action: nil)
    private let clearOnQuit = NSButton(checkboxWithTitle: "Clear history on quit", target: nil, action: nil)
    private let clearPeriodically = NSButton(checkboxWithTitle: "Clear history periodically", target: nil, action: nil)
    private let alertBeforeClear = NSButton(checkboxWithTitle: "Confirm before clearing history", target: nil, action: nil)
    private let observeScreenshots = NSButton(checkboxWithTitle: "Save screenshots into history", target: nil, action: nil)
    private let showColorPreview = NSButton(checkboxWithTitle: "Show color preview in menu", target: nil, action: nil)
    private let showNumbersInMenu = NSButton(checkboxWithTitle: "Number history items in menu", target: nil, action: nil)
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuCountField = NSTextField(string: "")
    private let pastePlain = NSButton(checkboxWithTitle: "Modifier → paste as plain text", target: nil, action: nil)
    private let deleteHist = NSButton(checkboxWithTitle: "modifier → delete from history", target: nil, action: nil)
    private let pasteDelete = NSButton(checkboxWithTitle: "modifier → paste and delete", target: nil, action: nil)
    private let pasteAuto = NSButton(checkboxWithTitle: "Paste automatically (off = copy only)", target: nil, action: nil)
    private let showStatusItem = NSButton(checkboxWithTitle: "Show menu bar icon", target: nil, action: nil)
    private let plainModPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let deleteModPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pasteDeleteModPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    // Menu layout
    private let snippetsAbove = NSButton(checkboxWithTitle: "Show snippets above history in main menu", target: nil, action: nil)
    private let showClearInMenu = NSButton(checkboxWithTitle: "Show Clear History in menu", target: nil, action: nil)
    private let showToolTips = NSButton(checkboxWithTitle: "Show tooltips on menu items", target: nil, action: nil)
    private let showImages = NSButton(checkboxWithTitle: "Show image thumbnails in menu", target: nil, action: nil)
    private let showIcons = NSButton(checkboxWithTitle: "Show icons in menu items", target: nil, action: nil)
    private let startsAtZero = NSButton(checkboxWithTitle: "Start numbering at 0", target: nil, action: nil)
    private let numericKeys = NSButton(checkboxWithTitle: "Number keys as shortcuts", target: nil, action: nil)
    private let inlineLimitField = NSTextField(string: "")
    private let folderLimitField = NSTextField(string: "")
    private let titleLenField = NSTextField(string: "")
    private var excludedTable: NSTableView!
    private var excludedIDs: [String] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blitz Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        reloadFromStore()
    }

    deinit { stopRecording() }

    func show() {
        reloadFromStore()
        store.didOpenSettingsOnce = true
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        NSApp.setActivationPolicy(.accessory)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalToConstant: 500),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        // Hotkeys
        stack.addArrangedSubview(sectionHeader("Hotkeys"))
        for field in [hotKeyField, clipboardHotKeyField, snippetsHotKeyField, mainMenuHotKeyField] {
            field.isEditable = false
            field.isBordered = true
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
            field.alignment = .center
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 140).isActive = true
        }
        recordButton.target = self
        recordButton.action = #selector(toggleRecordLauncher)
        stack.addArrangedSubview(hotRow("Launcher", field: hotKeyField, record: #selector(toggleRecordLauncher), reset: #selector(resetHotKey), resetTitle: "Reset ⌃⌥Space"))
        stack.addArrangedSubview(hotRow("Clipboard", field: clipboardHotKeyField, record: #selector(toggleRecordClipboard), reset: #selector(resetClipboardHotKey), resetTitle: "Reset ⌃⌥V"))
        stack.addArrangedSubview(hotRow("Snippets", field: snippetsHotKeyField, record: #selector(toggleRecordSnippets), reset: #selector(resetSnippetsHotKey), resetTitle: "Reset ⇧⌘B"))
        stack.addArrangedSubview(hotRow("Main menu", field: mainMenuHotKeyField, record: #selector(toggleRecordMainMenu), reset: #selector(resetMainMenuHotKey), resetTitle: "Reset ⌥⌘V"))

        hotKeyHint.stringValue = "Clipy-style: left-click menu bar for history · Main menu at mouse · modifiers on menu items."
        hotKeyHint.textColor = .secondaryLabelColor
        hotKeyHint.font = .systemFont(ofSize: 11)
        hotKeyHint.isEditable = false
        hotKeyHint.isBordered = false
        hotKeyHint.backgroundColor = .clear
        hotKeyHint.maximumNumberOfLines = 4
        hotKeyHint.lineBreakMode = .byWordWrapping
        hotKeyHint.preferredMaxLayoutWidth = 500
        stack.addArrangedSubview(hotKeyHint)

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("General"))
        loginCheckbox.target = self; loginCheckbox.action = #selector(toggleLogin)
        welcomeCheckbox.target = self; welcomeCheckbox.action = #selector(toggleWelcome)
        stack.addArrangedSubview(loginCheckbox)
        stack.addArrangedSubview(welcomeCheckbox)
        let openAX = NSButton(title: "Request Accessibility…", target: self, action: #selector(requestAX))
        accessibilityLabel.isEditable = false
        accessibilityLabel.isBordered = false
        accessibilityLabel.backgroundColor = .clear
        accessibilityLabel.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(NSStackView(views: [openAX, accessibilityLabel]))
        stack.addArrangedSubview(NSButton(title: "Edit Snippets…", target: self, action: #selector(openSnippets)))
        stack.addArrangedSubview(NSButton(title: "Edit Quicklinks & Scripts…", target: self, action: #selector(openCatalogs)))

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("Extensions"))
        stack.addArrangedSubview(NSButton(title: "Open Extensions Folder…", target: self, action: #selector(openExtensions)))
        stack.addArrangedSubview(NSButton(title: "Reload Extensions", target: self, action: #selector(reloadExtensions)))
        let extHint = NSTextField(labelWithString: "Drop a folder with extension.json into Application Support/Blitz/Extensions.")
        extHint.textColor = .secondaryLabelColor
        extHint.font = .systemFont(ofSize: 11)
        extHint.isEditable = false
        extHint.isBordered = false
        extHint.backgroundColor = .clear
        stack.addArrangedSubview(extHint)

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("iCloud sync"))
        iCloudSyncCheckbox.target = self
        iCloudSyncCheckbox.action = #selector(iCloudPrefsChanged)
        iCloudClipboardCheckbox.target = self
        iCloudClipboardCheckbox.action = #selector(iCloudPrefsChanged)
        stack.addArrangedSubview(iCloudSyncCheckbox)
        stack.addArrangedSubview(iCloudClipboardCheckbox)
        iCloudStatusLabel.font = .systemFont(ofSize: 11)
        iCloudStatusLabel.textColor = .secondaryLabelColor
        iCloudStatusLabel.isEditable = false
        iCloudStatusLabel.isBordered = false
        iCloudStatusLabel.backgroundColor = .clear
        stack.addArrangedSubview(iCloudStatusLabel)
        stack.addArrangedSubview(NSButton(title: "Sync Now", target: self, action: #selector(syncNow)))

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("Clipboard types"))
        let typeDefs: [(String, WritableKeyPath<PasteboardTypeSettings, Bool>)] = [
            ("Plain text", \.string),
            ("Images", \.tiff),
            ("RTF", \.rtf),
            ("HTML", \.html),
            ("PDF", \.pdf),
            ("Filenames", \.filenames),
            ("URLs", \.url)
        ]
        typeChecks = typeDefs.map { title, _ in
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(typesChanged))
            return b
        }
        let typeRow = NSStackView(views: typeChecks)
        typeRow.orientation = .horizontal
        typeRow.spacing = 10
        stack.addArrangedSubview(typeRow)

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("Clipboard privacy & history"))
        for b in [ignoreConcealed, ignoreUniversal, overwriteSame, copySame, reorderAfterPaste,
                  clearOnQuit, clearPeriodically, alertBeforeClear, observeScreenshots,
                  showColorPreview, showNumbersInMenu, pasteAuto, showStatusItem,
                  pastePlain, deleteHist, pasteDelete] {
            b.target = self
            b.action = #selector(clipboardPrefsChanged)
            stack.addArrangedSubview(b)
        }

        for (popup, label) in [
            (plainModPopup, "Plain-text modifier"),
            (deleteModPopup, "Delete modifier"),
            (pasteDeleteModPopup, "Paste+delete modifier")
        ] as [(NSPopUpButton, String)] {
            popup.removeAllItems()
            for m in ModifierActionKey.allCases {
                let name: String
                switch m {
                case .command: name = "⌘ Command"
                case .shift: name = "⇧ Shift"
                case .control: name = "⌃ Control"
                case .option: name = "⌥ Option"
                }
                popup.addItem(withTitle: name)
                popup.lastItem?.tag = m.rawValue
            }
            popup.target = self
            popup.action = #selector(clipboardPrefsChanged)
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: label), popup]))
        }

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("Menu layout (Clipy-style)"))
        for b in [snippetsAbove, showClearInMenu, showToolTips, showImages, showIcons, startsAtZero, numericKeys] {
            b.target = self
            b.action = #selector(clipboardPrefsChanged)
            stack.addArrangedSubview(b)
        }
        for (field, label, action) in [
            (inlineLimitField, "Inline history items (0=all folders)", #selector(menuLayoutFieldsChanged)),
            (folderLimitField, "Items per folder", #selector(menuLayoutFieldsChanged)),
            (titleLenField, "Max title length", #selector(menuLayoutFieldsChanged))
        ] as [(NSTextField, String, Selector)] {
            field.target = self
            field.action = action
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 56).isActive = true
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: label), field]))
        }

        intervalPopup.removeAllItems()
        for iv in HistoryClearInterval.allCases {
            intervalPopup.addItem(withTitle: iv.title)
            intervalPopup.lastItem?.tag = iv.rawValue
        }
        intervalPopup.target = self
        intervalPopup.action = #selector(clipboardPrefsChanged)
        stack.addArrangedSubview(NSStackView(views: [
            NSTextField(labelWithString: "Clear interval"),
            intervalPopup
        ]))

        configureNumeric(field: clipboardField, stepper: clipboardStepper, min: 20, max: 1000,
                         fieldAction: #selector(clipboardFieldChanged), stepperAction: #selector(clipboardStepperChanged))
        stack.addArrangedSubview(labeledRow("History size", field: clipboardField, stepper: clipboardStepper))

        menuCountField.target = self
        menuCountField.action = #selector(menuCountChanged)
        menuCountField.translatesAutoresizingMaskIntoConstraints = false
        menuCountField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(NSStackView(views: [
            NSTextField(labelWithString: "Menu history items"),
            menuCountField
        ]))

        configureNumeric(field: fileLimitField, stepper: fileLimitStepper, min: 10, max: 100,
                         fieldAction: #selector(fileLimitFieldChanged), stepperAction: #selector(fileLimitStepperChanged))
        stack.addArrangedSubview(labeledRow("File search results", field: fileLimitField, stepper: fileLimitStepper))

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("Excluded apps (not recorded)"))
        let exclScroll = NSScrollView()
        exclScroll.translatesAutoresizingMaskIntoConstraints = false
        exclScroll.hasVerticalScroller = true
        exclScroll.borderType = .bezelBorder
        exclScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        exclScroll.widthAnchor.constraint(equalToConstant: 500).isActive = true
        let table = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bid"))
        col.width = 460
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        exclScroll.documentView = table
        excludedTable = table
        stack.addArrangedSubview(exclScroll)
        let exclBtns = NSStackView(views: [
            NSButton(title: "Exclude Frontmost App", target: self, action: #selector(excludeFrontmost)),
            NSButton(title: "Remove Selected", target: self, action: #selector(removeExcluded))
        ])
        exclBtns.orientation = .horizontal
        stack.addArrangedSubview(exclBtns)

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionHeader("Panel size"))
        for f in [widthField, heightField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.widthAnchor.constraint(equalToConstant: 72).isActive = true
            f.target = self
            f.action = #selector(panelSizeChanged)
        }
        stack.addArrangedSubview(NSStackView(views: [
            NSTextField(labelWithString: "Width"), widthField,
            NSTextField(labelWithString: "Height"), heightField,
            NSButton(title: "Apply", target: self, action: #selector(panelSizeChanged))
        ]))

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(NSButton(title: "Clear Clipboard History", target: self, action: #selector(clearClipboard)))
        let about = NSTextField(labelWithString: "Blitz \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3") · Clipy-parity clipboard")
        about.textColor = .tertiaryLabelColor
        about.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(about)
    }

    private func hotRow(_ title: String, field: NSTextField, record: Selector, reset: Selector, resetTitle: String) -> NSStackView {
        let rec = NSButton(title: "Record…", target: self, action: record)
        let rst = NSButton(title: resetTitle, target: self, action: reset)
        let row = NSStackView(views: [NSTextField(labelWithString: title), field, rec, rst])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let t = NSTextField(labelWithString: title)
        t.font = .boldSystemFont(ofSize: 13)
        return t
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 500).isActive = true
        return box
    }

    private func labeledRow(_ title: String, field: NSTextField, stepper: NSStepper) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 160).isActive = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let row = NSStackView(views: [label, field, stepper])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func configureNumeric(
        field: NSTextField, stepper: NSStepper, min: Double, max: Double,
        fieldAction: Selector, stepperAction: Selector
    ) {
        field.target = self
        field.action = fieldAction
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = 10
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = stepperAction
    }

    func numberOfRows(in tableView: NSTableView) -> Int { excludedIDs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: excludedIDs[row])
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func reloadFromStore() {
        hotKeyField.stringValue = store.hotKeyDisplayString
        clipboardHotKeyField.stringValue = store.clipboardHotKeyDisplayString
        snippetsHotKeyField.stringValue = store.snippetsHotKeyDisplayString
        mainMenuHotKeyField.stringValue = store.mainMenuHotKeyDisplayString
        loginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        welcomeCheckbox.state = store.showWelcomeOnLaunch ? .on : .off
        iCloudSyncCheckbox.state = store.iCloudSyncEnabled ? .on : .off
        iCloudClipboardCheckbox.state = store.iCloudSyncClipboardText ? .on : .off
        iCloudStatusLabel.stringValue = iCloudSyncService.shared.statusMessage
        clipboardField.stringValue = "\(store.clipboardMaxItems)"
        clipboardStepper.integerValue = store.clipboardMaxItems
        fileLimitField.stringValue = "\(store.fileSearchLimit)"
        fileLimitStepper.integerValue = store.fileSearchLimit
        widthField.stringValue = "\(Int(store.panelWidth))"
        heightField.stringValue = "\(Int(store.panelHeight))"
        menuCountField.stringValue = "\(store.menuHistoryCount)"

        let t = store.pasteboardTypes
        let flags = [t.string, t.tiff, t.rtf, t.html, t.pdf, t.filenames, t.url]
        for (i, b) in typeChecks.enumerated() where i < flags.count {
            b.state = flags[i] ? .on : .off
        }

        ignoreConcealed.state = store.ignoreConcealed ? .on : .off
        ignoreUniversal.state = store.ignoreUniversalClipboard ? .on : .off
        overwriteSame.state = store.overwriteSameHistory ? .on : .off
        copySame.state = store.copySameHistory ? .on : .off
        reorderAfterPaste.state = store.reorderAfterPaste ? .on : .off
        clearOnQuit.state = store.clearHistoryOnQuit ? .on : .off
        clearPeriodically.state = store.clearHistoryPeriodically ? .on : .off
        alertBeforeClear.state = store.showAlertBeforeClearHistory ? .on : .off
        observeScreenshots.state = store.observeScreenshots ? .on : .off
        showColorPreview.state = store.showColorPreviewInMenu ? .on : .off
        showNumbersInMenu.state = store.showNumbersInMenu ? .on : .off
        pastePlain.state = store.pastePlainTextEnabled ? .on : .off
        deleteHist.state = store.deleteHistoryEnabled ? .on : .off
        pasteDelete.state = store.pasteAndDeleteEnabled ? .on : .off
        pasteAuto.state = store.pasteAutomatically ? .on : .off
        showStatusItem.state = store.showStatusItem ? .on : .off
        plainModPopup.selectItem(withTag: store.pastePlainTextModifier.rawValue)
        deleteModPopup.selectItem(withTag: store.deleteHistoryModifier.rawValue)
        pasteDeleteModPopup.selectItem(withTag: store.pasteAndDeleteModifier.rawValue)
        snippetsAbove.state = store.showsSnippetsAboveHistory ? .on : .off
        showClearInMenu.state = store.showsClearHistoryMenuItem ? .on : .off
        showToolTips.state = store.showToolTipsInMenu ? .on : .off
        showImages.state = store.showImagesInMenu ? .on : .off
        showIcons.state = store.showIconsInMenu ? .on : .off
        startsAtZero.state = store.startsMenuAtZero ? .on : .off
        numericKeys.state = store.addsNumericKeyEquivalents ? .on : .off
        inlineLimitField.stringValue = "\(store.inlineMenuItemLimit)"
        folderLimitField.stringValue = "\(store.folderMenuItemLimit)"
        titleLenField.stringValue = "\(store.maxMenuTitleLength)"
        intervalPopup.selectItem(withTag: store.historyClearInterval.rawValue)

        excludedIDs = store.excludedBundleIDs
        excludedTable?.reloadData()
        refreshAccessibilityLabel()
    }

    func updateHotKeyStatus(_ message: String) {
        guard !message.isEmpty else { return }
        hotKeyHint.stringValue = message
        hotKeyHint.textColor = message.lowercased().contains("fail") ? .systemOrange : .secondaryLabelColor
        hotKeyField.stringValue = store.hotKeyDisplayString
        clipboardHotKeyField.stringValue = store.clipboardHotKeyDisplayString
        snippetsHotKeyField.stringValue = store.snippetsHotKeyDisplayString
        mainMenuHotKeyField.stringValue = store.mainMenuHotKeyDisplayString
    }

    private func refreshAccessibilityLabel() {
        let ok = Accessibility.trusted
        accessibilityLabel.stringValue = ok ? "Accessibility: granted" : "Accessibility: needed for paste"
        accessibilityLabel.textColor = ok ? .systemGreen : .systemOrange
    }

    @objc private func typesChanged() {
        var t = store.pasteboardTypes
        if typeChecks.count >= 7 {
            t.string = typeChecks[0].state == .on
            t.tiff = typeChecks[1].state == .on
            t.rtf = typeChecks[2].state == .on
            t.html = typeChecks[3].state == .on
            t.pdf = typeChecks[4].state == .on
            t.filenames = typeChecks[5].state == .on
            t.url = typeChecks[6].state == .on
        }
        store.pasteboardTypes = t
        settingsDelegate?.settingsDidChangeClipboardPrefs()
    }

    @objc private func clipboardPrefsChanged() {
        store.ignoreConcealed = ignoreConcealed.state == .on
        store.ignoreUniversalClipboard = ignoreUniversal.state == .on
        store.overwriteSameHistory = overwriteSame.state == .on
        store.copySameHistory = copySame.state == .on
        store.reorderAfterPaste = reorderAfterPaste.state == .on
        store.clearHistoryOnQuit = clearOnQuit.state == .on
        store.clearHistoryPeriodically = clearPeriodically.state == .on
        store.showAlertBeforeClearHistory = alertBeforeClear.state == .on
        store.observeScreenshots = observeScreenshots.state == .on
        store.showColorPreviewInMenu = showColorPreview.state == .on
        store.showNumbersInMenu = showNumbersInMenu.state == .on
        store.pastePlainTextEnabled = pastePlain.state == .on
        store.deleteHistoryEnabled = deleteHist.state == .on
        store.pasteAndDeleteEnabled = pasteDelete.state == .on
        store.pasteAutomatically = pasteAuto.state == .on
        store.showStatusItem = showStatusItem.state == .on
        if let m = ModifierActionKey(rawValue: plainModPopup.selectedItem?.tag ?? 0) {
            store.pastePlainTextModifier = m
        }
        if let m = ModifierActionKey(rawValue: deleteModPopup.selectedItem?.tag ?? 3) {
            store.deleteHistoryModifier = m
        }
        if let m = ModifierActionKey(rawValue: pasteDeleteModPopup.selectedItem?.tag ?? 1) {
            store.pasteAndDeleteModifier = m
        }
        store.showsSnippetsAboveHistory = snippetsAbove.state == .on
        store.showsClearHistoryMenuItem = showClearInMenu.state == .on
        store.showToolTipsInMenu = showToolTips.state == .on
        store.showImagesInMenu = showImages.state == .on
        store.showIconsInMenu = showIcons.state == .on
        store.startsMenuAtZero = startsAtZero.state == .on
        store.addsNumericKeyEquivalents = numericKeys.state == .on
        if let tag = intervalPopup.selectedItem?.tag,
           let iv = HistoryClearInterval(rawValue: tag) {
            store.historyClearInterval = iv
        }
        settingsDelegate?.settingsDidChangeClipboardPrefs()
    }

    @objc private func menuLayoutFieldsChanged() {
        store.inlineMenuItemLimit = Int(inlineLimitField.stringValue) ?? store.inlineMenuItemLimit
        store.folderMenuItemLimit = Int(folderLimitField.stringValue) ?? store.folderMenuItemLimit
        store.maxMenuTitleLength = Int(titleLenField.stringValue) ?? store.maxMenuTitleLength
        inlineLimitField.stringValue = "\(store.inlineMenuItemLimit)"
        folderLimitField.stringValue = "\(store.folderMenuItemLimit)"
        titleLenField.stringValue = "\(store.maxMenuTitleLength)"
        settingsDelegate?.settingsDidChangeClipboardPrefs()
    }

    @objc private func menuCountChanged() {
        store.menuHistoryCount = Int(menuCountField.stringValue) ?? store.menuHistoryCount
        menuCountField.stringValue = "\(store.menuHistoryCount)"
        settingsDelegate?.settingsDidChangeClipboardPrefs()
    }

    @objc private func excludeFrontmost() {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        // Prefer previous app if Blitz itself is frontmost
        var id = bid
        if id == Bundle.main.bundleIdentifier {
            // keep as-is; user can exclude while another app is front after focusing settings
        }
        if !excludedIDs.contains(id) {
            // Also try to get app that isn't Blitz from workspace
            if id.contains("blitz") || id == "research.reversedir.blitz" {
                if let other = NSWorkspace.shared.runningApplications.first(where: {
                    $0.activationPolicy == .regular &&
                    $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
                    $0.bundleIdentifier != nil
                })?.bundleIdentifier {
                    id = other
                }
            }
            excludedIDs.append(id)
            store.excludedBundleIDs = excludedIDs
            excludedTable.reloadData()
            settingsDelegate?.settingsDidChangeClipboardPrefs()
        }
    }

    @objc private func removeExcluded() {
        let row = excludedTable.selectedRow
        guard row >= 0, row < excludedIDs.count else { return }
        excludedIDs.remove(at: row)
        store.excludedBundleIDs = excludedIDs
        excludedTable.reloadData()
        settingsDelegate?.settingsDidChangeClipboardPrefs()
    }

    @objc private func openSnippets() {
        NotificationCenter.default.post(name: .blitzOpenSnippets, object: nil)
    }

    @objc private func openCatalogs() {
        NotificationCenter.default.post(name: .blitzOpenCatalogs, object: nil, userInfo: ["scripts": false])
    }

    @objc private func openExtensions() {
        ExtensionStore.shared.openExtensionsFolder()
    }

    @objc private func reloadExtensions() {
        ExtensionStore.shared.load()
    }

    @objc private func iCloudPrefsChanged() {
        store.iCloudSyncEnabled = iCloudSyncCheckbox.state == .on
        store.iCloudSyncClipboardText = iCloudClipboardCheckbox.state == .on
        if store.iCloudSyncEnabled {
            iCloudSyncService.shared.start()
        } else {
            iCloudSyncService.shared.stop()
        }
        iCloudStatusLabel.stringValue = iCloudSyncService.shared.statusMessage
    }

    @objc private func syncNow() {
        iCloudSyncService.shared.pullNow()
        iCloudSyncService.shared.pushNow()
        iCloudStatusLabel.stringValue = iCloudSyncService.shared.statusMessage + " · synced"
    }

    @objc private func toggleRecordLauncher() {
        if recordingHotKey { stopRecording(); return }
        startRecording(target: .launcher)
    }

    @objc private func toggleRecordClipboard() {
        if recordingHotKey { stopRecording(); return }
        startRecording(target: .clipboard)
    }

    @objc private func toggleRecordSnippets() {
        if recordingHotKey { stopRecording(); return }
        startRecording(target: .snippets)
    }

    @objc private func toggleRecordMainMenu() {
        if recordingHotKey { stopRecording(); return }
        startRecording(target: .mainMenu)
    }

    private func startRecording(target: RecordingTarget) {
        recordingTarget = target
        recordingHotKey = true
        let field: NSTextField
        switch target {
        case .launcher: field = hotKeyField
        case .clipboard: field = clipboardHotKeyField
        case .snippets: field = snippetsHotKeyField
        case .mainMenu: field = mainMenuHotKeyField
        }
        field.stringValue = "…"
        field.textColor = .systemOrange
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecorded(event)
            return nil
        }
    }

    private func stopRecording() {
        recordingHotKey = false
        for f in [hotKeyField, clipboardHotKeyField, snippetsHotKeyField, mainMenuHotKeyField] {
            f.textColor = .labelColor
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        hotKeyField.stringValue = store.hotKeyDisplayString
        clipboardHotKeyField.stringValue = store.clipboardHotKeyDisplayString
        snippetsHotKeyField.stringValue = store.snippetsHotKeyDisplayString
        mainMenuHotKeyField.stringValue = store.mainMenuHotKeyDisplayString
    }

    private func handleRecorded(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let mods = HotKeyCodec.carbonModifiers(from: event.modifierFlags)
        guard mods != 0 else {
            hotKeyHint.stringValue = "Add ⌘ / ⌥ / ⌃ / ⇧ — bare keys are reserved by the system."
            return
        }
        if UInt32(event.keyCode) == UInt32(kVK_Space) && mods == UInt32(optionKey) {
            hotKeyHint.stringValue = "⌥Space is used by Raycast. Try ⌃⌥Space instead."
            hotKeyHint.textColor = .systemOrange
            return
        }
        switch recordingTarget {
        case .launcher:
            store.hotKeyCode = UInt32(event.keyCode)
            store.hotKeyModifiers = mods
        case .clipboard:
            store.clipboardHotKeyCode = UInt32(event.keyCode)
            store.clipboardHotKeyModifiers = mods
        case .snippets:
            store.snippetsHotKeyCode = UInt32(event.keyCode)
            store.snippetsHotKeyModifiers = mods
        case .mainMenu:
            store.mainMenuHotKeyCode = UInt32(event.keyCode)
            store.mainMenuHotKeyModifiers = mods
            // Avoid colliding with clipboard panel chord.
            if store.mainMenuHotKeyCode == store.clipboardHotKeyCode
                && store.mainMenuHotKeyModifiers == store.clipboardHotKeyModifiers {
                store.mainMenuHotKeyModifiers = UInt32(optionKey | cmdKey)
                hotKeyHint.stringValue = "Main matched Clipboard — remapped to ⌥⌘V"
                hotKeyHint.textColor = .systemOrange
            }
        }
        stopRecording()
        settingsDelegate?.settingsDidChangeHotKey()
        if hotKeyHint.textColor != .systemOrange {
            hotKeyHint.stringValue = "Saved — \(store.hotKeyDisplayString) · clip \(store.clipboardHotKeyDisplayString) · main \(store.mainMenuHotKeyDisplayString)"
            hotKeyHint.textColor = .systemGreen
        }
    }

    @objc private func resetHotKey() {
        store.resetHotKeyToDefault()
        stopRecording()
        reloadFromStore()
        settingsDelegate?.settingsDidChangeHotKey()
    }

    @objc private func resetClipboardHotKey() {
        store.resetClipboardHotKeyToDefault()
        stopRecording()
        reloadFromStore()
        settingsDelegate?.settingsDidChangeHotKey()
    }

    @objc private func resetSnippetsHotKey() {
        store.resetSnippetsHotKeyToDefault()
        stopRecording()
        reloadFromStore()
        settingsDelegate?.settingsDidChangeHotKey()
    }

    @objc private func resetMainMenuHotKey() {
        store.resetMainMenuHotKeyToDefault()
        stopRecording()
        reloadFromStore()
        settingsDelegate?.settingsDidChangeHotKey()
    }

    @objc private func toggleLogin() { LaunchAtLogin.isEnabled = loginCheckbox.state == .on }
    @objc private func toggleWelcome() { store.showWelcomeOnLaunch = welcomeCheckbox.state == .on }

    @objc private func clipboardFieldChanged() {
        applyClipboardMax(Int(clipboardField.stringValue) ?? store.clipboardMaxItems)
    }

    @objc private func clipboardStepperChanged() {
        applyClipboardMax(clipboardStepper.integerValue)
    }

    private func applyClipboardMax(_ value: Int) {
        store.clipboardMaxItems = value
        clipboardField.stringValue = "\(store.clipboardMaxItems)"
        clipboardStepper.integerValue = store.clipboardMaxItems
        ClipboardStore.shared.applyMaxItems(store.clipboardMaxItems)
        settingsDelegate?.settingsDidChangeClipboardPrefs()
    }

    @objc private func fileLimitFieldChanged() {
        applyFileLimit(Int(fileLimitField.stringValue) ?? store.fileSearchLimit)
    }

    @objc private func fileLimitStepperChanged() {
        applyFileLimit(fileLimitStepper.integerValue)
    }

    private func applyFileLimit(_ value: Int) {
        store.fileSearchLimit = value
        fileLimitField.stringValue = "\(store.fileSearchLimit)"
        fileLimitStepper.integerValue = store.fileSearchLimit
    }

    @objc private func panelSizeChanged() {
        let w = CGFloat(Double(widthField.stringValue) ?? Double(store.panelWidth))
        let h = CGFloat(Double(heightField.stringValue) ?? Double(store.panelHeight))
        store.panelWidth = w
        store.panelHeight = h
        widthField.stringValue = "\(Int(store.panelWidth))"
        heightField.stringValue = "\(Int(store.panelHeight))"
        settingsDelegate?.settingsDidChangePanelSize()
    }

    @objc private func requestAX() {
        Accessibility.requestPrompt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshAccessibilityLabel()
        }
    }

    @objc private func clearClipboard() {
        ClipboardStore.shared.clear(confirm: true)
    }
}

extension Notification.Name {
    static let blitzShowPanel = Notification.Name("blitz.showPanel")
    static let blitzOpenSettings = Notification.Name("blitz.openSettings")
    static let blitzOpenSnippets = Notification.Name("blitz.openSnippets")
    static let blitzShowClipboard = Notification.Name("blitz.showClipboard")
    static let blitzOpenCatalogs = Notification.Name("blitz.openCatalogs")
}
