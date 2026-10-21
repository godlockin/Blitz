import AppKit
import Carbon

struct SnippetFolder: Codable, Identifiable {
    var id: String
    var name: String
    var snippets: [Snippet]
    /// Optional global hotkey to pop this folder's snippet menu (Clipy folderKeyCombos).
    var hotKeyCode: UInt32?
    var hotKeyModifiers: UInt32?

    enum CodingKeys: String, CodingKey {
        case id, name, snippets, hotKeyCode, hotKeyModifiers
    }
}

struct Snippet: Codable, Identifiable {
    var id: String
    var keyword: String
    var content: String
    var enabled: Bool
    var folderId: String

    init(id: String = UUID().uuidString, keyword: String, content: String, enabled: Bool = true, folderId: String) {
        self.id = id
        self.keyword = keyword
        self.content = content
        self.enabled = enabled
        self.folderId = folderId
    }
}

final class SnippetStore {
    static let shared = SnippetStore()

    private(set) var folders: [SnippetFolder] = []
    private var monitor: Any?
    private var buffer = ""

    private var storeURL: URL {
        BlitzDatabase.supportDirectory.appendingPathComponent("snippets.json")
    }

    var allEnabledSnippets: [Snippet] {
        folders.flatMap { $0.snippets.filter(\.enabled) }
    }

    func load() {
        BlitzDatabase.shared.migrateSnippetsJSONIfNeeded(jsonURL: storeURL)
        folders = BlitzDatabase.shared.loadFolders()
        if folders.isEmpty {
            let fid = UUID().uuidString
            folders = [
                SnippetFolder(id: fid, name: "General", snippets: [
                    Snippet(keyword: ";sig", content: "Best regards,\nBlitz User", folderId: fid),
                    Snippet(keyword: ";addr", content: "123 Example Street", folderId: fid)
                ])
            ]
            save()
        }
        startMonitor()
    }

    func save() {
        BlitzDatabase.shared.replaceFolders(folders)
        // Mirror JSON for iCloud Drive sync / backup.
        if let data = try? JSONEncoder().encode(folders) {
            try? data.write(to: storeURL, options: .atomic)
        }
        iCloudSyncService.shared.pushNow()
    }

    /// Reload folders from `snippets.json` (used after iCloud pull).
    func reloadFromDiskJSON() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([SnippetFolder].self, from: data),
              !decoded.isEmpty else { return }
        folders = decoded
        BlitzDatabase.shared.replaceFolders(folders)
    }

    func addFolder(name: String) {
        folders.append(SnippetFolder(id: UUID().uuidString, name: name, snippets: []))
        save()
    }

    func removeFolder(id: String) {
        folders.removeAll { $0.id == id }
        if folders.isEmpty {
            addFolder(name: "General")
        } else {
            save()
        }
    }

    func setFolderHotKey(id: String, keyCode: UInt32?, modifiers: UInt32?) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].hotKeyCode = keyCode
        folders[idx].hotKeyModifiers = modifiers
        save()
    }

    func folderHotKeyDisplay(id: String) -> String {
        guard let folder = folders.first(where: { $0.id == id }),
              let code = folder.hotKeyCode,
              let mods = folder.hotKeyModifiers,
              mods != 0 else { return "(none)" }
        return HotKeyCodec.displayString(keyCode: code, modifiers: mods)
    }

    func upsert(_ snippet: Snippet) {
        guard let fIdx = folders.firstIndex(where: { $0.id == snippet.folderId }) else { return }
        if let sIdx = folders[fIdx].snippets.firstIndex(where: { $0.id == snippet.id }) {
            folders[fIdx].snippets[sIdx] = snippet
        } else {
            folders[fIdx].snippets.append(snippet)
        }
        save()
    }

    func deleteSnippet(id: String) {
        for i in folders.indices {
            folders[i].snippets.removeAll { $0.id == id }
        }
        save()
    }

    func exportJSON() -> Data? {
        try? JSONEncoder().encode(folders)
    }

    func importJSON(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode([SnippetFolder].self, from: data), !decoded.isEmpty else {
            return false
        }
        folders = decoded
        save()
        return true
    }

    func pasteSnippet(_ snippet: Snippet) {
        PasteHelper.captureFrontApp()
        ClipboardStore.shared.suppressNextCapture(for: 1.5)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snippet.content, forType: .string)
        ClipboardStore.shared.notePasteboardWritten()
        // Reuse paste pipeline with a transient text item
        let id = UUID().uuidString
        let item = ClipboardItem(id: id, kind: .text, text: snippet.content)
        // Don't add to history — paste directly
        PasteHelper.pasteTextDirect(snippet.content)
        _ = item
    }

    private func startMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        guard Accessibility.trusted else { return }
        if event.modifierFlags.contains(.command)
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.option) {
            return
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        if chars.isEmpty { return }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            if !buffer.isEmpty { buffer.removeLast() }
            return
        }
        if chars == "\r" || chars == "\n" || chars == "\t" || chars == " " {
            buffer = ""
            return
        }
        buffer += chars
        if buffer.count > 32 { buffer = String(buffer.suffix(32)) }
        guard let match = allEnabledSnippets.first(where: { buffer.hasSuffix($0.keyword) }) else { return }
        expand(match)
        buffer = ""
    }

    private func expand(_ snippet: Snippet) {
        let source = CGEventSource(stateID: .hidSystemState)
        let deleteCode: CGKeyCode = 51
        for _ in 0..<snippet.keyword.count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: deleteCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: deleteCode, keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
        ClipboardStore.shared.suppressNextCapture(for: 1.5)
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(snippet.content, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            PasteHelper.postCommandV()
            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    pb.clearContents()
                    pb.setString(previous, forType: .string)
                    ClipboardStore.shared.notePasteboardWritten()
                }
            }
        }
    }
}
