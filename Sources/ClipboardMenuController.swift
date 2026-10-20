import AppKit

/// Clipy-style history / main / snippet menus with inline+folder paging and menu prefs.
enum ClipboardMenuController {
    /// History-only menu (numbered, folderized when over inline limit).
    static func populateHistory(into menu: NSMenu, target: AnyObject, action: Selector) {
        menu.removeAllItems()
        let store = SettingsStore.shared
        let all = Array(ClipboardStore.shared.items.prefix(store.menuHistoryCount))
        if all.isEmpty {
            let empty = NSMenuItem(title: "(empty)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            appendFooter(to: menu, target: target, includeClear: true)
            return
        }

        let inlineLimit = store.inlineMenuItemLimit
        let folderSize = max(1, store.folderMenuItemLimit)
        let startNumber = store.startsMenuAtZero ? 0 : 1

        if inlineLimit <= 0 {
            // All history in folders of `folderSize`
            addFolderized(items: all, into: menu, target: target, action: action, startNumber: startNumber, folderSize: folderSize)
        } else {
            let inline = Array(all.prefix(inlineLimit))
            addFlatItems(inline, into: menu, target: target, action: action, startNumber: startNumber, assignKeys: true)
            let rest = Array(all.dropFirst(inlineLimit))
            if !rest.isEmpty {
                menu.addItem(.separator())
                addFolderized(items: rest, into: menu, target: target, action: action,
                              startNumber: startNumber + inline.count, folderSize: folderSize)
            }
        }

        appendFooter(to: menu, target: target, includeClear: true)
    }

    /// Combined main menu: optional snippets above/below history (Clipy main menu).
    static func populateMain(into menu: NSMenu, target: AnyObject, historyAction: Selector, snippetAction: Selector) {
        menu.removeAllItems()
        let store = SettingsStore.shared
        if store.showsSnippetsAboveHistory {
            addSnippetSection(into: menu, target: target, action: snippetAction)
            menu.addItem(.separator())
            populateHistoryCore(into: menu, target: target, action: historyAction)
        } else {
            populateHistoryCore(into: menu, target: target, action: historyAction)
            menu.addItem(.separator())
            addSnippetSection(into: menu, target: target, action: snippetAction)
        }
        appendFooter(to: menu, target: target, includeClear: true)
    }

    static func populateSnippets(into menu: NSMenu, target: AnyObject, action: Selector) {
        menu.removeAllItems()
        addSnippetSection(into: menu, target: target, action: action, withFolders: true)
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Snippets…", action: #selector(AppDelegate.openSnippetEditor), keyEquivalent: "")
        edit.target = target
        menu.addItem(edit)
    }

    static func popUpAtMouse(_ menu: NSMenu) {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    static func handleSelection(id: String) {
        let flags = NSEvent.modifierFlags
        let store = SettingsStore.shared

        // ⌃ = toggle pin (reserved; not used by Clipy-style paste modifiers)
        if flags.contains(.control)
            && !store.deleteHistoryModifier.isPressed(in: flags)
            && !store.pastePlainTextModifier.isPressed(in: flags)
            && !store.pasteAndDeleteModifier.isPressed(in: flags) {
            _ = ClipboardStore.shared.togglePin(id: id)
            return
        }

        let deleteOnly = store.deleteHistoryEnabled && store.deleteHistoryModifier.isPressed(in: flags)
            && !(store.pasteAndDeleteEnabled && store.pasteAndDeleteModifier.isPressed(in: flags))
        if deleteOnly {
            ClipboardStore.shared.delete(id: id)
            return
        }

        let plain = store.pastePlainTextEnabled && store.pastePlainTextModifier.isPressed(in: flags)
        let pasteDelete = store.pasteAndDeleteEnabled && store.pasteAndDeleteModifier.isPressed(in: flags)

        PasteHelper.captureFrontApp()
        if !store.pasteAutomatically {
            if let item = ClipboardStore.shared.items.first(where: { $0.id == id }) {
                ClipboardStore.shared.writeToPasteboard(item, plainText: plain)
                if pasteDelete { ClipboardStore.shared.delete(id: id) }
                else { ClipboardStore.shared.reorderAfterPaste(id: id) }
            }
            return
        }
        ClipboardStore.shared.paste(id, plainText: plain, deleteAfter: pasteDelete)
    }

    // MARK: - Build helpers

    private static func populateHistoryCore(into menu: NSMenu, target: AnyObject, action: Selector) {
        let store = SettingsStore.shared
        let all = Array(ClipboardStore.shared.items.prefix(store.menuHistoryCount))
        if all.isEmpty {
            let empty = NSMenuItem(title: "(empty)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let inlineLimit = store.inlineMenuItemLimit
        let folderSize = max(1, store.folderMenuItemLimit)
        let startNumber = store.startsMenuAtZero ? 0 : 1
        if inlineLimit <= 0 {
            addFolderized(items: all, into: menu, target: target, action: action, startNumber: startNumber, folderSize: folderSize)
        } else {
            let inline = Array(all.prefix(inlineLimit))
            addFlatItems(inline, into: menu, target: target, action: action, startNumber: startNumber, assignKeys: true)
            let rest = Array(all.dropFirst(inlineLimit))
            if !rest.isEmpty {
                menu.addItem(.separator())
                addFolderized(items: rest, into: menu, target: target, action: action,
                              startNumber: startNumber + inline.count, folderSize: folderSize)
            }
        }
    }

    private static func addFlatItems(
        _ items: [ClipboardItem],
        into menu: NSMenu,
        target: AnyObject,
        action: Selector,
        startNumber: Int,
        assignKeys: Bool
    ) {
        let store = SettingsStore.shared
        for (offset, item) in items.enumerated() {
            let listNumber = startNumber + offset
            let mi = makeHistoryItem(item, listNumber: listNumber, target: target, action: action)
            if assignKeys, store.addsNumericKeyEquivalents, offset < 10 {
                let keyNum = store.startsMenuAtZero ? (listNumber % 10) : ((offset + 1) % 10)
                mi.keyEquivalent = "\(keyNum)"
                mi.keyEquivalentModifierMask = []
            }
            menu.addItem(mi)
        }
    }

    private static func addFolderized(
        items: [ClipboardItem],
        into menu: NSMenu,
        target: AnyObject,
        action: Selector,
        startNumber: Int,
        folderSize: Int
    ) {
        var offset = 0
        var folderIndex = 0
        while offset < items.count {
            let slice = Array(items[offset..<min(offset + folderSize, items.count)])
            let first = startNumber + offset
            let last = first + slice.count - 1
            let folderItem = NSMenuItem(title: "\(first)-\(last)", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            addFlatItems(slice, into: sub, target: target, action: action, startNumber: first, assignKeys: folderIndex == 0)
            folderItem.submenu = sub
            if SettingsStore.shared.showIconsInMenu {
                folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            }
            menu.addItem(folderItem)
            offset += slice.count
            folderIndex += 1
        }
    }

    private static func makeHistoryItem(
        _ item: ClipboardItem,
        listNumber: Int,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let store = SettingsStore.shared
        let title = menuTitle(for: item, listNumber: listNumber)
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = target
        mi.representedObject = item.id
        if store.showToolTipsInMenu {
            mi.toolTip = tooltip(for: item, max: store.maxToolTipLength)
        }
        if item.kind == .color, store.showColorPreviewInMenu,
           let parsed = ColorParse.parse(item.text) {
            mi.image = ColorParse.swatchImage(parsed.color, size: 14)
        } else if store.showImagesInMenu, item.kind == .image,
                  let url = ClipboardStore.shared.imageURL(for: item),
                  let img = NSImage(contentsOf: url) {
            mi.image = thumbnail(img, width: store.thumbnailWidth, height: store.thumbnailHeight)
        } else if store.showIconsInMenu {
            mi.image = kindIcon(item.kind)
        }
        return mi
    }

    private static func addSnippetSection(
        into menu: NSMenu,
        target: AnyObject,
        action: Selector,
        withFolders: Bool = false
    ) {
        let store = SettingsStore.shared
        let folders = SnippetStore.shared.folders
        if folders.isEmpty {
            let empty = NSMenuItem(title: "(no snippets)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        var index = store.startsMenuAtZero ? 0 : 1
        for folder in folders {
            let enabled = folder.snippets.filter(\.enabled)
            guard !enabled.isEmpty else { continue }
            if withFolders || folders.count > 1 {
                let folderItem = NSMenuItem(title: folder.name, action: nil, keyEquivalent: "")
                if store.showIconsInMenu {
                    folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                }
                let sub = NSMenu()
                for s in enabled {
                    sub.addItem(makeSnippetItem(s, listNumber: index, target: target, action: action))
                    index += 1
                }
                folderItem.submenu = sub
                menu.addItem(folderItem)
            } else {
                for s in enabled {
                    menu.addItem(makeSnippetItem(s, listNumber: index, target: target, action: action))
                    index += 1
                }
            }
        }
    }

    private static func makeSnippetItem(
        _ snippet: Snippet,
        listNumber: Int,
        target: AnyObject,
        action: Selector
    ) -> NSMenuItem {
        let store = SettingsStore.shared
        var title = snippet.keyword.isEmpty ? oneLine(snippet.content, max: store.maxMenuTitleLength)
            : "\(snippet.keyword) — \(oneLine(snippet.content, max: max(20, store.maxMenuTitleLength - 12)))"
        if store.showNumbersInMenu {
            title = "\(listNumber). " + title
        }
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = target
        mi.representedObject = snippet.id
        if store.showToolTipsInMenu {
            mi.toolTip = oneLine(snippet.content, max: store.maxToolTipLength)
        }
        if store.showIconsInMenu {
            mi.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        }
        return mi
    }

    private static func appendFooter(to menu: NSMenu, target: AnyObject, includeClear: Bool) {
        let store = SettingsStore.shared
        menu.addItem(.separator())
        let hint = NSMenuItem(
            title: modifierHint(store),
            action: nil,
            keyEquivalent: ""
        )
        hint.isEnabled = false
        menu.addItem(hint)
        if includeClear, store.showsClearHistoryMenuItem {
            let clear = NSMenuItem(title: "Clear History", action: #selector(AppDelegate.clearClipboard), keyEquivalent: "")
            clear.target = target
            menu.addItem(clear)
        }
    }

    private static func modifierHint(_ store: SettingsStore) -> String {
        var parts: [String] = ["⌃ pin"]
        if store.pastePlainTextEnabled { parts.append("\(store.pastePlainTextModifier.displayName) plain") }
        if store.deleteHistoryEnabled { parts.append("\(store.deleteHistoryModifier.displayName) delete") }
        if store.pasteAndDeleteEnabled { parts.append("\(store.pasteAndDeleteModifier.displayName) paste+del") }
        return parts.joined(separator: " · ")
    }

    private static func menuTitle(for item: ClipboardItem, listNumber: Int) -> String {
        let store = SettingsStore.shared
        let prefix = store.showNumbersInMenu ? "\(listNumber). " : ""
        let pin = item.pinned ? "★ " : ""
        let body: String
        switch item.kind {
        case .image: body = item.text
        case .color: body = item.text
        case .file: body = (item.text.split(separator: "\n").first.map(String.init) ?? item.text)
        case .url: body = item.text
        case .pdf: body = "PDF"
        case .rtf: body = "RTF · " + oneLine(item.text)
        case .html: body = "HTML · " + oneLine(item.text)
        case .text: body = oneLine(item.text)
        }
        let maxLen = max(8, store.maxMenuTitleLength)
        let clipped = body.count > maxLen ? String(body.prefix(maxLen)) + "…" : body
        return prefix + pin + clipped
    }

    private static func tooltip(for item: ClipboardItem, max: Int) -> String {
        if let ocr = item.ocrText, !ocr.isEmpty {
            return "OCR: " + oneLine(ocr, max: max)
        }
        return oneLine(item.text, max: max)
    }

    private static func oneLine(_ s: String, max: Int = 80) -> String {
        let p = s.replacingOccurrences(of: "\n", with: " ")
        return p.count > max ? String(p.prefix(max)) + "…" : p
    }

    private static func kindIcon(_ kind: ClipboardKind) -> NSImage? {
        let name: String
        switch kind {
        case .text: name = "doc.plaintext"
        case .image: name = "photo"
        case .rtf, .html: name = "doc.richtext"
        case .pdf: name = "doc.fill"
        case .file: name = "doc"
        case .url: name = "link"
        case .color: name = "paintpalette"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private static func thumbnail(_ image: NSImage, width: CGFloat, height: CGFloat) -> NSImage {
        let size = image.size
        let scale = min(width / Swift.max(size.width, 1), height / Swift.max(size.height, 1), 1)
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let out = NSImage(size: target)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        out.unlockFocus()
        return out
    }
}
