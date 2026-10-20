import AppKit

/// Edit launcher quicklinks and local script commands.
final class CatalogEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Mode: Int { case quicklinks = 0, scripts = 1 }

    private var mode: Mode = .quicklinks
    private var table: NSTableView!
    private var nameField: NSTextField!
    private var valueField: NSTextField!
    private var hintLabel: NSTextField!
    private var selectedID: String?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Blitz Quicklinks & Scripts"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        buildUI()
        reload()
    }

    func showEditor(preferScripts: Bool = false) {
        mode = preferScripts ? .scripts : .quicklinks
        if let seg = window?.contentView?.viewWithTag(9001) as? NSSegmentedControl {
            seg.selectedSegment = mode.rawValue
        }
        applyModeChrome()
        reload()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let seg = NSSegmentedControl(labels: ["Quicklinks", "Scripts"], trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
        seg.selectedSegment = 0
        seg.tag = 9001
        seg.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let tv = NSTableView()
        let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        colName.title = "Name"
        colName.width = 180
        let colValue = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        colValue.title = "URL / Command"
        colValue.width = 400
        tv.addTableColumn(colName)
        tv.addTableColumn(colValue)
        tv.delegate = self
        tv.dataSource = self
        tv.target = self
        tv.action = #selector(rowClicked)
        scroll.documentView = tv
        table = tv

        nameField = NSTextField(string: "")
        nameField.placeholderString = "Name"
        nameField.delegate = self
        valueField = NSTextField(string: "")
        valueField.placeholderString = "https://… or shell command"
        valueField.delegate = self

        hintLabel = NSTextField(labelWithString: "")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.maximumNumberOfLines = 2
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.preferredMaxLayoutWidth = 600

        let addBtn = NSButton(title: "Add", target: self, action: #selector(addItem))
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveItem))
        let delBtn = NSButton(title: "Delete", target: self, action: #selector(deleteItem))
        let btns = NSStackView(views: [addBtn, saveBtn, delBtn])
        btns.orientation = .horizontal
        btns.spacing = 8

        let form = NSStackView(views: [
            NSTextField(labelWithString: "Name"),
            nameField,
            NSTextField(labelWithString: "Value"),
            valueField,
            hintLabel,
            btns
        ])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 6
        form.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(seg)
        content.addSubview(scroll)
        content.addSubview(form)

        NSLayoutConstraint.activate([
            seg.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            seg.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            scroll.topAnchor.constraint(equalTo: seg.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.heightAnchor.constraint(equalToConstant: 200),

            form.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 14),
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            form.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            form.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),

            nameField.widthAnchor.constraint(equalTo: form.widthAnchor),
            valueField.widthAnchor.constraint(equalTo: form.widthAnchor)
        ])

        applyModeChrome()
    }

    private func applyModeChrome() {
        switch mode {
        case .quicklinks:
            valueField.placeholderString = "https://example.com/search?q={Query}"
            hintLabel.stringValue = "Use {Query} for the text after the quicklink name in the launcher (e.g. “Google blitz”)."
            table.tableColumns[0].title = "Name"
            table.tableColumns[1].title = "URL"
        case .scripts:
            valueField.placeholderString = "open -a Terminal \"$HOME\""
            hintLabel.stringValue = "Runs via /bin/zsh -lc. Prefer simple local commands; no interactive prompts."
            table.tableColumns[0].title = "Title"
            table.tableColumns[1].title = "Command"
        }
    }

    private func reload() {
        selectedID = nil
        nameField.stringValue = ""
        valueField.stringValue = ""
        table.reloadData()
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        mode = Mode(rawValue: sender.selectedSegment) ?? .quicklinks
        applyModeChrome()
        reload()
    }

    @objc private func rowClicked() {
        let row = table.selectedRow
        guard row >= 0 else { return }
        switch mode {
        case .quicklinks:
            let items = QuicklinkStore.shared.items
            guard row < items.count else { return }
            let item = items[row]
            selectedID = item.id
            nameField.stringValue = item.name
            valueField.stringValue = item.url
        case .scripts:
            let items = ScriptCommandStore.shared.items
            guard row < items.count else { return }
            let item = items[row]
            selectedID = item.id
            nameField.stringValue = item.title
            valueField.stringValue = item.command
        }
    }

    @objc private func addItem() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = valueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = name.isEmpty ? (mode == .quicklinks ? "New Link" : "New Script") : name
        let v = value.isEmpty
            ? (mode == .quicklinks ? "https://example.com" : "echo hello")
            : value
        switch mode {
        case .quicklinks:
            selectedID = QuicklinkStore.shared.add(name: n, url: v)
        case .scripts:
            selectedID = ScriptCommandStore.shared.add(title: n, command: v)
        }
        table.reloadData()
        selectCurrent()
    }

    @objc private func saveItem() {
        guard let id = selectedID else {
            addItem()
            return
        }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = valueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else { return }
        switch mode {
        case .quicklinks:
            QuicklinkStore.shared.update(id: id, name: name, url: value)
        case .scripts:
            ScriptCommandStore.shared.update(id: id, title: name, command: value)
        }
        table.reloadData()
        selectCurrent()
    }

    @objc private func deleteItem() {
        guard let id = selectedID else { return }
        switch mode {
        case .quicklinks:
            QuicklinkStore.shared.delete(id: id)
        case .scripts:
            ScriptCommandStore.shared.delete(id: id)
        }
        selectedID = nil
        nameField.stringValue = ""
        valueField.stringValue = ""
        table.reloadData()
    }

    private func selectCurrent() {
        guard let id = selectedID else { return }
        let ids: [String]
        switch mode {
        case .quicklinks: ids = QuicklinkStore.shared.items.map(\.id)
        case .scripts: ids = ScriptCommandStore.shared.items.map(\.id)
        }
        if let idx = ids.firstIndex(of: id) {
            table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        switch mode {
        case .quicklinks: return QuicklinkStore.shared.items.count
        case .scripts: return ScriptCommandStore.shared.items.count
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        switch mode {
        case .quicklinks:
            let item = QuicklinkStore.shared.items[row]
            text = tableColumn?.identifier.rawValue == "name" ? item.name : item.url
        case .scripts:
            let item = ScriptCommandStore.shared.items[row]
            text = tableColumn?.identifier.rawValue == "name" ? item.title : item.command
        }
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
