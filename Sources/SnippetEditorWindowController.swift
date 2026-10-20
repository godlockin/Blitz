import AppKit
import Carbon
import UniformTypeIdentifiers

/// Simple folder + snippet editor (Clipy-inspired, clean-room).
final class SnippetEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let store = SnippetStore.shared
    private var folderTable: NSTableView!
    private var snippetTable: NSTableView!
    private var keywordField: NSTextField!
    private var contentView: NSTextView!
    private var enabledCheckbox: NSButton!
    private var folderHotKeyLabel: NSTextField!
    private var selectedFolderId: String?
    private var selectedSnippetId: String?
    private var recordingFolderHotKey = false
    private var keyMonitor: Any?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blitz Snippets"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        buildUI()
        reload()
    }

    func showEditor() {
        reload()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let folderScroll = makeTable(identifier: "folders") { t in folderTable = t }
        let snippetScroll = makeTable(identifier: "snippets") { t in snippetTable = t }

        keywordField = NSTextField(string: "")
        keywordField.placeholderString = "Keyword (e.g. ;sig)"
        keywordField.delegate = self

        enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: self, action: #selector(enabledChanged))

        let scroll = NSScrollView()
        let tv = NSTextView()
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.delegate = self
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        contentView = tv

        let addFolder = NSButton(title: "+ Folder", target: self, action: #selector(addFolder))
        let delFolder = NSButton(title: "− Folder", target: self, action: #selector(deleteFolder))
        let addSnippet = NSButton(title: "+ Snippet", target: self, action: #selector(addSnippet))
        let delSnippet = NSButton(title: "− Snippet", target: self, action: #selector(deleteSnippet))
        let exportBtn = NSButton(title: "Export…", target: self, action: #selector(exportSnippets))
        let importBtn = NSButton(title: "Import…", target: self, action: #selector(importSnippets))
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveCurrent))
        let recordFolderHK = NSButton(title: "Record Folder Hotkey…", target: self, action: #selector(recordFolderHotKey))
        let clearFolderHK = NSButton(title: "Clear Hotkey", target: self, action: #selector(clearFolderHotKey))
        folderHotKeyLabel = NSTextField(labelWithString: "Folder hotkey: (none)")
        folderHotKeyLabel.textColor = .secondaryLabelColor
        folderHotKeyLabel.font = .systemFont(ofSize: 11)

        let leftStack = NSStackView(views: [
            NSTextField(labelWithString: "Folders"),
            folderScroll,
            NSStackView(views: [addFolder, delFolder]),
            folderHotKeyLabel,
            NSStackView(views: [recordFolderHK, clearFolderHK])
        ])
        leftStack.orientation = .vertical
        leftStack.spacing = 6

        let midStack = NSStackView(views: [
            NSTextField(labelWithString: "Snippets"),
            snippetScroll,
            NSStackView(views: [addSnippet, delSnippet])
        ])
        midStack.orientation = .vertical
        midStack.spacing = 6

        let rightStack = NSStackView(views: [
            NSTextField(labelWithString: "Keyword"),
            keywordField,
            enabledCheckbox,
            NSTextField(labelWithString: "Content"),
            scroll,
            NSStackView(views: [saveBtn, exportBtn, importBtn])
        ])
        rightStack.orientation = .vertical
        rightStack.spacing = 6
        rightStack.alignment = .leading

        let split = NSStackView(views: [leftStack, midStack, rightStack])
        split.orientation = .horizontal
        split.spacing = 12
        split.distribution = .fill
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        folderScroll.translatesAutoresizingMaskIntoConstraints = false
        snippetScroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            leftStack.widthAnchor.constraint(equalToConstant: 160),
            midStack.widthAnchor.constraint(equalToConstant: 200),
            folderScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            snippetScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            keywordField.widthAnchor.constraint(equalTo: rightStack.widthAnchor)
        ])
    }

    private func makeTable(identifier: String, assign: (NSTableView) -> Void) -> NSScrollView {
        let table = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        col.title = identifier.capitalized
        col.width = 140
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(tableClicked(_:))
        table.identifier = NSUserInterfaceItemIdentifier(identifier)
        assign(table)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    private func reload() {
        folderTable.reloadData()
        if selectedFolderId == nil { selectedFolderId = store.folders.first?.id }
        if let fid = selectedFolderId, let idx = store.folders.firstIndex(where: { $0.id == fid }) {
            folderTable.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
        snippetTable.reloadData()
        loadEditorFields()
    }

    private var currentFolder: SnippetFolder? {
        store.folders.first { $0.id == selectedFolderId }
    }

    private var currentSnippet: Snippet? {
        currentFolder?.snippets.first { $0.id == selectedSnippetId }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == folderTable { return store.folders.count }
        return currentFolder?.snippets.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        if tableView == folderTable {
            let f = store.folders[row]
            let hk = store.folderHotKeyDisplay(id: f.id)
            field.stringValue = hk == "(none)" ? f.name : "\(f.name) [\(hk)]"
        } else if let snips = currentFolder?.snippets, row < snips.count {
            let s = snips[row]
            field.stringValue = (s.enabled ? "" : "⊘ ") + (s.keyword.isEmpty ? "(no keyword)" : s.keyword)
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func tableClicked(_ sender: NSTableView) {
        if sender == folderTable {
            let row = sender.selectedRow
            guard row >= 0, row < store.folders.count else { return }
            selectedFolderId = store.folders[row].id
            selectedSnippetId = store.folders[row].snippets.first?.id
            snippetTable.reloadData()
            loadEditorFields()
        } else {
            let row = sender.selectedRow
            guard let snips = currentFolder?.snippets, row >= 0, row < snips.count else { return }
            selectedSnippetId = snips[row].id
            loadEditorFields()
        }
    }

    private func loadEditorFields() {
        if let fid = selectedFolderId {
            folderHotKeyLabel.stringValue = "Folder hotkey: \(store.folderHotKeyDisplay(id: fid))"
        } else {
            folderHotKeyLabel.stringValue = "Folder hotkey: (none)"
        }
        guard let s = currentSnippet else {
            keywordField.stringValue = ""
            contentView.string = ""
            enabledCheckbox.state = .on
            return
        }
        keywordField.stringValue = s.keyword
        contentView.string = s.content
        enabledCheckbox.state = s.enabled ? .on : .off
    }

    @objc private func recordFolderHotKey() {
        guard selectedFolderId != nil else { return }
        recordingFolderHotKey = true
        folderHotKeyLabel.stringValue = "Press shortcut… (Esc cancel)"
        folderHotKeyLabel.textColor = .systemOrange
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleFolderHotKeyRecord(event)
            return nil
        }
    }

    @objc private func clearFolderHotKey() {
        guard let fid = selectedFolderId else { return }
        store.setFolderHotKey(id: fid, keyCode: nil, modifiers: nil)
        HotKeyManager.shared.register(autoFallback: true)
        reload()
    }

    private func handleFolderHotKeyRecord(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopFolderHotKeyRecord()
            return
        }
        let mods = HotKeyCodec.carbonModifiers(from: event.modifierFlags)
        guard mods != 0, let fid = selectedFolderId else { return }
        store.setFolderHotKey(id: fid, keyCode: UInt32(event.keyCode), modifiers: mods)
        HotKeyManager.shared.register(autoFallback: true)
        stopFolderHotKeyRecord()
        reload()
    }

    private func stopFolderHotKeyRecord() {
        recordingFolderHotKey = false
        folderHotKeyLabel.textColor = .secondaryLabelColor
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        loadEditorFields()
    }

    @objc private func saveCurrent() {
        guard var s = currentSnippet else { return }
        s.keyword = keywordField.stringValue
        s.content = contentView.string
        s.enabled = enabledCheckbox.state == .on
        store.upsert(s)
        reload()
    }

    @objc private func enabledChanged() { saveCurrent() }

    @objc private func addFolder() {
        store.addFolder(name: "Folder \(store.folders.count + 1)")
        selectedFolderId = store.folders.last?.id
        reload()
    }

    @objc private func deleteFolder() {
        guard let id = selectedFolderId else { return }
        store.removeFolder(id: id)
        selectedFolderId = store.folders.first?.id
        selectedSnippetId = nil
        reload()
    }

    @objc private func addSnippet() {
        guard let fid = selectedFolderId else { return }
        let s = Snippet(keyword: ";new", content: "New snippet", folderId: fid)
        store.upsert(s)
        selectedSnippetId = s.id
        reload()
    }

    @objc private func deleteSnippet() {
        guard let id = selectedSnippetId else { return }
        store.deleteSnippet(id: id)
        selectedSnippetId = currentFolder?.snippets.first?.id
        reload()
    }

    @objc private func exportSnippets() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "blitz-snippets.json"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    @objc private func importSnippets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            if SnippetStore.shared.importJSON(data) {
                self?.selectedFolderId = SnippetStore.shared.folders.first?.id
                self?.reload()
            }
        }
    }
}

extension SnippetEditorWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        // Autosave on edit is optional; explicit Save button is primary.
    }
}
