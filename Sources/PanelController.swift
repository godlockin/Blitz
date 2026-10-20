import AppKit

enum PanelMode {
    case launcher
    case clipboard
}

/// Search panel in pure AppKit (WebKit previously hung on this machine).
final class PanelController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSPanel?
    private var queryField: NSTextField!
    private var metaLabel: NSTextField!
    private var tableView: NSTableView!
    private var items: [SearchItem] = []
    private var didPrepare = false
    private var keyMonitor: Any?
    private var searchGeneration: UInt64 = 0
    private var debounceWork: DispatchWorkItem?
    private(set) var mode: PanelMode = .launcher
    var onOpenSettings: (() -> Void)?

    func prepare() {
        if window != nil { return }
        FileLogger.log("prepare step1")

        let store = SettingsStore.shared
        let width = max(store.panelWidth, 480)
        let height = max(store.panelHeight, 320)
        let size = NSSize(width: width, height: height)

        // Create off-screen first; show() will center on the active display.
        let panel = NSPanel(
            contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        FileLogger.log("prepare step2 panel")
        panel.title = "Blitz"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // macOS 26+: canJoinAllSpaces and moveToActiveSpace are mutually exclusive.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.15, alpha: 1)
        panel.hasShadow = true

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = root
        // Assign early so a later hang still leaves a usable window reference.
        window = panel
        didPrepare = true
        FileLogger.log("prepare step3 contentView")

        let query = NSTextField(string: "")
        query.placeholderString = "Apps · files · clip · win · snippets · quicklinks"
        query.font = .systemFont(ofSize: 20)
        // placeholder updated in applyModeUI()
        query.isBordered = false
        query.drawsBackground = false
        query.focusRingType = .none
        query.textColor = .white
        query.delegate = self
        query.frame = NSRect(x: 18, y: size.height - 52, width: size.width - 60, height: 30)
        query.autoresizingMask = [.width, .minYMargin]
        root.addSubview(query)
        queryField = query

        let gear = NSButton(frame: NSRect(x: size.width - 40, y: size.height - 52, width: 28, height: 28))
        gear.title = "⚙"
        gear.bezelStyle = .inline
        gear.isBordered = false
        gear.target = self
        gear.action = #selector(openSettingsClicked)
        gear.autoresizingMask = [.minXMargin, .minYMargin]
        root.addSubview(gear)
        FileLogger.log("prepare step4 query")

        let meta = NSTextField(labelWithString: "")
        meta.frame = NSRect(x: 18, y: size.height - 74, width: size.width - 36, height: 16)
        meta.font = .systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor
        meta.autoresizingMask = [.width, .minYMargin]
        root.addSubview(meta)
        metaLabel = meta
        updateMeta()

        let table = NSTableView(frame: .zero)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 64
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(activateSelection)
        table.allowsEmptySelection = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.width = size.width - 24
        table.addTableColumn(col)
        tableView = table

        let scroll = NSScrollView(frame: NSRect(x: 8, y: 8, width: size.width - 16, height: size.height - 90))
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        scroll.autoresizingMask = [.width, .height]
        root.addSubview(scroll)
        FileLogger.log("prepare done")
    }

    private func updateMeta() {
        let store = SettingsStore.shared
        switch mode {
        case .launcher:
            let tools = [ToolPath.fd != nil ? "fd" : nil, ToolPath.rg != nil ? "rg" : nil]
                .compactMap { $0 }.joined(separator: "+")
            let engine = tools.isEmpty ? "mdfind" : tools
            metaLabel?.stringValue = "Blitz · \(store.hotKeyDisplayString) · clip \(store.clipboardHotKeyDisplayString) · files:\(engine)"
        case .clipboard:
            metaLabel?.stringValue = "Clipboard · Enter paste · ⌘P pin · \(store.clipboardHotKeyDisplayString)"
        }
    }

    private func applyModeUI() {
        switch mode {
        case .launcher:
            queryField?.placeholderString = "Apps · files · clip · win · snippets · quicklinks"
            tableView?.rowHeight = 56
        case .clipboard:
            queryField?.placeholderString = "Filter clipboard history…"
            tableView?.rowHeight = 72
        }
        updateMeta()
    }

    private func ensureKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    func applyPanelSize() {
        guard let window else { return }
        let store = SettingsStore.shared
        window.setContentSize(NSSize(width: store.panelWidth, height: store.panelHeight))
    }

    func toggle(mode: PanelMode = .launcher) {
        if window == nil { prepare() }
        guard let window else { return }
        if window.isVisible && window.isOnActiveSpace && isWindowOnAnyScreen(window) && self.mode == mode {
            hide()
        } else {
            show(mode: mode)
        }
    }

    private func isWindowOnAnyScreen(_ window: NSWindow) -> Bool {
        let frame = window.frame
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    func show(mode: PanelMode = .launcher) {
        // Remember who had the text cursor before we steal focus.
        PasteHelper.captureFrontApp()

        self.mode = mode
        if window == nil { prepare() }
        guard let window else {
            FileLogger.log("show failed — no window")
            return
        }
        applyPanelSize()
        applyModeUI()
        ensureKeyMonitor()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen {
            let vf = screen.visibleFrame
            let size = window.frame.size
            let origin = NSPoint(
                x: vf.midX - size.width / 2,
                y: vf.midY - size.height / 2 + 40
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.orderFrontRegardless()

        if mode == .clipboard {
            // Keep the original app key so its text caret stays alive.
            // We still briefly become key so Enter/arrows work in the panel.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(queryField)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(queryField)
        }

        queryField?.stringValue = ""
        refresh()
        FileLogger.log("panel show mode=\(mode) visible=\(window.isVisible) frame=\(NSStringFromRect(window.frame))")
    }

    func hide() {
        window?.orderOut(nil)
    }

    func refresh() {
        scheduleSearch(immediate: mode == .clipboard || (queryField?.stringValue.isEmpty ?? true))
    }

    /// Debounced async search so typing never blocks the UI.
    private func scheduleSearch(immediate: Bool) {
        debounceWork?.cancel()
        let delay: TimeInterval = immediate ? 0 : 0.12
        let work = DispatchWorkItem { [weak self] in
            self?.runSearch()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func runSearch() {
        let q = queryField?.stringValue ?? ""
        let currentMode = mode
        searchGeneration &+= 1
        let gen = searchGeneration

        if currentMode == .clipboard {
            items = ClipboardStore.shared.searchItems(query: q)
            applyItemsToTable()
            return
        }

        // Instant local results (calc / clipboard / apps) — no file I/O
        let quick = SearchService.searchQuick(query: q)
        items = quick
        applyItemsToTable()

        // File search off-main; skip if query empty
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let limit = SettingsStore.shared.fileSearchLimit
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = FileSearch.search(query: trimmed, limit: limit)
            DispatchQueue.main.async {
                guard let self, self.searchGeneration == gen, self.mode == .launcher else { return }
                // Merge: keep calc/clipboard/apps from quick, insert files after calc
                var merged = SearchService.searchQuick(query: q)
                let calcCount = merged.first?.kind == "calculator" ? 1 : 0
                merged.insert(contentsOf: files, at: min(calcCount, merged.count))
                self.items = Array(merged.prefix(60))
                self.applyItemsToTable()
            }
        }
    }

    private func applyItemsToTable() {
        tableView?.reloadData()
        if !items.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func openSettingsClicked() {
        hide()
        onOpenSettings?()
    }

    @objc private func activateSelection() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        if item.id == "cmd.settings" {
            hide()
            onOpenSettings?()
            return
        }

        // Clipboard mode (and clipboard items from launcher): paste into previous app at caret.
        if mode == .clipboard || item.kind == "clipboard" {
            if item.id == "cmd.clipboard.clear" {
                ClipboardStore.shared.clear()
                refresh()
                return
            }
            guard item.id.hasPrefix("clip:") else { return }
            let clipId = String(item.id.dropFirst(5))
            // Order: capture already done on show; hide first so we are not the key window.
            window?.orderOut(nil)
            PasteHelper.pasteClipboardItem(id: clipId)
            return
        }

        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            SearchService.run(id: item.id, kind: item.kind)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard window?.isVisible == true else { return event }

        // Never swallow standard editing shortcuts — let the text field handle them.
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if mods == .command,
           let ch = event.charactersIgnoringModifiers?.lowercased(),
           ["v", "c", "x", "a", "z"].contains(ch) {
            return event
        }

        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
            openSettingsClicked()
            return nil
        }
        // ⌘P — pin / unpin selected clipboard item
        if mods == .command,
           event.charactersIgnoringModifiers?.lowercased() == "p",
           mode == .clipboard || (tableView.selectedRow >= 0 && tableView.selectedRow < items.count && items[tableView.selectedRow].kind == "clipboard") {
            togglePinSelection()
            return nil
        }
        switch event.keyCode {
        case 125: moveSelection(1); return nil
        case 126: moveSelection(-1); return nil
        case 36, 76: activateSelection(); return nil
        case 53: hide(); return nil
        default: return event
        }
    }

    private func togglePinSelection() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        guard item.kind == "clipboard", item.id.hasPrefix("clip:") else { return }
        let clipId = String(item.id.dropFirst(5))
        let pinned = ClipboardStore.shared.togglePin(id: clipId)
        FileLogger.log(pinned ? "pinned \(clipId)" : "unpinned \(clipId)")
        scheduleSearch(immediate: true)
    }

    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + delta, 0), items.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func controlTextDidChange(_ obj: Notification) {
        scheduleSearch(immediate: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let id = NSUserInterfaceItemIdentifier("BlitzRow")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? BlitzRowView) ?? BlitzRowView()
        cell.identifier = id
        cell.configure(item)
        return cell
    }
}

private final class BlitzRowView: NSTableCellView {
    private let thumb = NSImageView()
    private let textThumb = NSTextField(wrappingLabelWithString: "")
    private let thumbBox = NSView()
    private let badge = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")

    private let thumbSize: CGFloat = 56

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        thumbBox.wantsLayer = true
        thumbBox.layer?.cornerRadius = 8
        thumbBox.layer?.masksToBounds = true
        thumbBox.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        thumbBox.layer?.borderWidth = 1
        thumbBox.layer?.borderColor = NSColor(calibratedWhite: 0.28, alpha: 1).cgColor
        thumbBox.translatesAutoresizingMaskIntoConstraints = false

        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.imageAlignment = .alignCenter
        thumb.translatesAutoresizingMaskIntoConstraints = false

        textThumb.font = .systemFont(ofSize: 9)
        textThumb.textColor = NSColor(calibratedWhite: 0.85, alpha: 1)
        textThumb.maximumNumberOfLines = 4
        textThumb.lineBreakMode = .byTruncatingTail
        textThumb.drawsBackground = false
        textThumb.isBordered = false
        textThumb.translatesAutoresizingMaskIntoConstraints = false

        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = NSColor(calibratedRed: 0.43, green: 0.66, blue: 1, alpha: 1)
        badge.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subLabel.font = .systemFont(ofSize: 11)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        thumbBox.addSubview(thumb)
        thumbBox.addSubview(textThumb)
        addSubview(thumbBox)
        addSubview(badge)
        addSubview(titleLabel)
        addSubview(subLabel)

        NSLayoutConstraint.activate([
            thumbBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbBox.widthAnchor.constraint(equalToConstant: thumbSize),
            thumbBox.heightAnchor.constraint(equalToConstant: thumbSize),

            thumb.topAnchor.constraint(equalTo: thumbBox.topAnchor),
            thumb.bottomAnchor.constraint(equalTo: thumbBox.bottomAnchor),
            thumb.leadingAnchor.constraint(equalTo: thumbBox.leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: thumbBox.trailingAnchor),

            textThumb.topAnchor.constraint(equalTo: thumbBox.topAnchor, constant: 4),
            textThumb.bottomAnchor.constraint(equalTo: thumbBox.bottomAnchor, constant: -4),
            textThumb.leadingAnchor.constraint(equalTo: thumbBox.leadingAnchor, constant: 4),
            textThumb.trailingAnchor.constraint(equalTo: thumbBox.trailingAnchor, constant: -4),

            badge.leadingAnchor.constraint(equalTo: thumbBox.trailingAnchor, constant: 10),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            subLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: SearchItem) {
        badge.stringValue = item.kind.uppercased()
        titleLabel.stringValue = item.title
        subLabel.stringValue = item.subtitle

        switch item.kind {
        case "calculator":
            badge.textColor = NSColor(calibratedRed: 0.49, green: 0.88, blue: 0.66, alpha: 1)
        case "command":
            badge.textColor = NSColor(calibratedRed: 0.79, green: 0.63, blue: 1, alpha: 1)
        case "clipboard":
            badge.textColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.35, alpha: 1)
        default:
            badge.textColor = NSColor(calibratedRed: 0.43, green: 0.66, blue: 1, alpha: 1)
        }

        // Thumbnail: image preview, text snippet, or kind glyph.
        if let path = item.preview, let img = NSImage(contentsOfFile: path) {
            thumb.image = Self.thumbnail(from: img, size: thumbSize)
            thumb.isHidden = false
            textThumb.isHidden = true
            textThumb.stringValue = ""
            if item.kind == "clipboard" { badge.stringValue = "IMAGE" }
        } else if item.kind == "clipboard" {
            thumb.image = nil
            thumb.isHidden = true
            textThumb.isHidden = false
            textThumb.stringValue = item.title
            textThumb.font = .systemFont(ofSize: 9)
            textThumb.alignment = .left
            badge.stringValue = "TEXT"
        } else {
            thumb.image = nil
            thumb.isHidden = true
            textThumb.isHidden = false
            textThumb.font = .systemFont(ofSize: 18, weight: .semibold)
            textThumb.alignment = .center
            textThumb.stringValue = Self.glyph(for: item.kind)
        }
    }

    private static func glyph(for kind: String) -> String {
        switch kind {
        case "app": return "A"
        case "file": return "F"
        case "calculator": return "="
        case "command": return "⌘"
        default: return "·"
        }
    }

    private static func thumbnail(from image: NSImage, size: CGFloat) -> NSImage {
        let target = NSSize(width: size * 2, height: size * 2) // retina-ish
        let result = NSImage(size: target)
        result.lockFocus()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: target)).fill()
        let src = image.size
        guard src.width > 0, src.height > 0 else {
            result.unlockFocus()
            return image
        }
        let scale = min(target.width / src.width, target.height / src.height)
        let drawSize = NSSize(width: src.width * scale, height: src.height * scale)
        let origin = NSPoint(
            x: (target.width - drawSize.width) / 2,
            y: (target.height - drawSize.height) / 2
        )
        image.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }
}
