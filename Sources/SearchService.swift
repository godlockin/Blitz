import AppKit

struct SearchItem: Codable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    /// Optional local file path for image preview in the panel.
    let preview: String?
}

enum SearchService {
    /// Called when user picks Open Settings from the panel.
    static var openSettingsHandler: (() -> Void)?

    /// Instant results only — no Spotlight / disk walks. Safe on main thread.
    static func searchQuick(query: String) -> [SearchItem] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = raw.lowercased()
        var items: [SearchItem] = []

        if let calc = Calculator.evaluate(raw) {
            items.append(SearchItem(
                id: "calc:" + calc,
                kind: "calculator",
                title: calc,
                subtitle: "= \(raw)  · Enter copies result",
                preview: nil
            ))
        }

        if q.isEmpty {
            items.append(contentsOf: ClipboardStore.shared.searchItems(query: "").prefix(12))
            items.append(contentsOf: commandCatalog(matching: ""))
            items.append(contentsOf: appItems(matching: "", limit: 10))
            return Array(items.prefix(50))
        }

        // Window management: "left", "右半", "maximize"…
        items.append(contentsOf: windowItems(matching: q))

        items.append(contentsOf: ClipboardStore.shared.searchItems(query: q))
        items.append(contentsOf: snippetItems(matching: q))
        items.append(contentsOf: quicklinkItems(matching: q, rawQuery: raw))
        items.append(contentsOf: scriptItems(matching: q))
        items.append(contentsOf: ExtensionStore.shared.searchItems(matching: q))
        items.append(contentsOf: EmojiCatalog.searchItems(matching: raw))
        items.append(contentsOf: commandCatalog(matching: q))
        items.append(contentsOf: appItems(matching: q, limit: 15))

        return Array(items.prefix(50))
    }

    /// Full search including files (files may block — prefer searchQuick + FileSearch async).
    static func search(query: String) -> [SearchItem] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = searchQuick(query: query)
        if raw.isEmpty { return items }
        let files = FileSearch.search(query: raw, limit: SettingsStore.shared.fileSearchLimit)
        let calcCount = items.first?.kind == "calculator" ? 1 : 0
        items.insert(contentsOf: files, at: min(calcCount, items.count))
        return Array(items.prefix(60))
    }

    // MARK: - Catalogs

    private static func commandCatalog(matching q: String) -> [SearchItem] {
        let all: [SearchItem] = [
            SearchItem(id: "cmd.settings", kind: "command", title: "Open Settings…",
                       subtitle: "Hotkeys · clipboard · menu  ·  ⌘,", preview: nil),
            SearchItem(id: "cmd.snippets", kind: "command", title: "Edit Snippets…",
                       subtitle: "Folders · keywords · import/export", preview: nil),
            SearchItem(id: "cmd.clipboard", kind: "command", title: "Clipboard History…",
                       subtitle: SettingsStore.shared.clipboardHotKeyDisplayString, preview: nil),
            SearchItem(id: "cmd.clipboard.clear", kind: "command", title: "Clear Clipboard History",
                       subtitle: "Remove all saved clips", preview: nil),
            SearchItem(id: "cmd.quicklinks", kind: "command", title: "Edit Quicklinks…",
                       subtitle: "Launcher URL shortcuts · {Query}", preview: nil),
            SearchItem(id: "cmd.scripts", kind: "command", title: "Edit Scripts…",
                       subtitle: "Local shell commands in launcher", preview: nil),
            SearchItem(id: "cmd.extensions", kind: "command", title: "Open Extensions Folder…",
                       subtitle: "Drop-in extension.json packages", preview: nil),
            SearchItem(id: "cmd.extensions.reload", kind: "command", title: "Reload Extensions",
                       subtitle: "Rescan Application Support/Blitz/Extensions", preview: nil),
            SearchItem(id: "cmd.emoji", kind: "command", title: "Emoji…",
                       subtitle: "Type emoji / 表情 + keyword in launcher", preview: nil),
        ]
        if q.isEmpty { return Array(all.prefix(4)) }
        return all.filter {
            $0.title.lowercased().contains(q)
                || $0.subtitle.lowercased().contains(q)
                || (q.contains("setting") || q.contains("设置") || q.contains("pref")) && $0.id == "cmd.settings"
                || (q.contains("snippet") || q.contains("片段")) && $0.id == "cmd.snippets"
                || (q.contains("clip") || q.contains("剪贴")) && $0.id.hasPrefix("cmd.clipboard")
                || (q.contains("clear") || q.contains("清空")) && $0.id == "cmd.clipboard.clear"
                || (q.contains("quick") || q.contains("link") || q.contains("快捷")) && $0.id == "cmd.quicklinks"
                || (q.contains("script") || q.contains("脚本")) && $0.id == "cmd.scripts"
                || (q.contains("ext") || q.contains("plugin") || q.contains("扩展")) && $0.id.hasPrefix("cmd.extensions")
                || (q.contains("emoji") || q.contains("表情")) && $0.id == "cmd.emoji"
        }
    }

    private static func windowItems(matching q: String) -> [SearchItem] {
        let catalog: [(String, String, String, WindowManager.Snap)] = [
            ("win:left", "Left Half", "Window · 左半屏", .leftHalf),
            ("win:right", "Right Half", "Window · 右半屏", .rightHalf),
            ("win:top", "Top Half", "Window · 上半屏", .topHalf),
            ("win:bottom", "Bottom Half", "Window · 下半屏", .bottomHalf),
            ("win:tl", "Top Left", "Window · 左上", .topLeft),
            ("win:tr", "Top Right", "Window · 右上", .topRight),
            ("win:bl", "Bottom Left", "Window · 左下", .bottomLeft),
            ("win:br", "Bottom Right", "Window · 右下", .bottomRight),
            ("win:max", "Maximize", "Window · 最大化", .maximize),
            ("win:center", "Center", "Window · 居中", .center),
        ]
        let aliases: [String: [String]] = [
            "win:left": ["left", "左", "左半"],
            "win:right": ["right", "右", "右半"],
            "win:top": ["top", "上", "上半"],
            "win:bottom": ["bottom", "下", "下半"],
            "win:tl": ["topleft", "左上"],
            "win:tr": ["topright", "右上"],
            "win:bl": ["bottomleft", "左下"],
            "win:br": ["bottomright", "右下"],
            "win:max": ["max", "maximize", "fullscreen", "最大", "全屏"],
            "win:center": ["center", "centre", "居中", "中间"],
        ]
        guard q.contains("win") || q.contains("窗口") || q.contains("半") || q.contains("屏")
            || aliases.values.contains(where: { $0.contains(where: { q.contains($0) }) })
            || ["left", "right", "top", "bottom", "max", "center", "centre"].contains(where: { q == $0 || q.hasPrefix($0) })
        else { return [] }

        return catalog.compactMap { id, title, subtitle, _ in
            let hit = title.lowercased().contains(q)
                || (aliases[id] ?? []).contains(where: { q.contains($0) || $0.contains(q) })
                || q.contains("win") || q.contains("窗口")
            guard hit else { return nil }
            return SearchItem(id: id, kind: "window", title: title, subtitle: subtitle, preview: nil)
        }
    }

    private static func snippetItems(matching q: String) -> [SearchItem] {
        SnippetStore.shared.allEnabledSnippets.compactMap { s in
            let hay = (s.keyword + " " + s.content).lowercased()
            guard hay.contains(q) || s.keyword.lowercased().hasPrefix(q) else { return nil }
            let preview = s.content.replacingOccurrences(of: "\n", with: " ")
            let title = s.keyword.isEmpty ? String(preview.prefix(60)) : s.keyword
            return SearchItem(
                id: "snip:" + s.id,
                kind: "snippet",
                title: title,
                subtitle: "Snippet · " + String(preview.prefix(80)),
                preview: nil
            )
        }
    }

    private static func quicklinkItems(matching q: String, rawQuery: String) -> [SearchItem] {
        QuicklinkStore.shared.items.compactMap { link in
            let name = link.name.lowercased()
            guard name.contains(q) || q.hasPrefix(name) || name.hasPrefix(q) else { return nil }
            // Remainder after name becomes {Query}
            var remainder = rawQuery
            if let range = remainder.range(of: link.name, options: .caseInsensitive) {
                remainder = String(remainder[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return SearchItem(
                id: "qlink:" + link.id + ":" + remainder,
                kind: "quicklink",
                title: link.name,
                subtitle: remainder.isEmpty ? link.url : "Search: \(remainder)",
                preview: nil
            )
        }
    }

    private static func scriptItems(matching q: String) -> [SearchItem] {
        ScriptCommandStore.shared.items.compactMap { s in
            guard s.title.lowercased().contains(q) || q.contains("script") || q.contains("脚本") else {
                return nil
            }
            return SearchItem(
                id: "script:" + s.id,
                kind: "script",
                title: s.title,
                subtitle: "Script · \(s.command)",
                preview: nil
            )
        }
    }

    private static func appItems(matching q: String, limit: Int) -> [SearchItem] {
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleURL != nil }
                .prefix(limit)
                .compactMap { app in
                    guard let url = app.bundleURL else { return nil }
                    let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
                    return SearchItem(
                        id: "app:" + url.path,
                        kind: "app",
                        title: name,
                        subtitle: "Application",
                        preview: nil
                    )
                }
        }

        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var seen = Set<String>()
        var result: [SearchItem] = []
        let ql = query.lowercased()

        for dir in roots {
            guard let apps = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for appURL in apps where appURL.pathExtension == "app" {
                let name = appURL.deletingPathExtension().lastPathComponent
                let key = name.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)
                guard FileSearch.matchScore(fileName: name, query: ql) != nil || key.contains(ql) else { continue }
                result.append(SearchItem(
                    id: "app:" + appURL.path,
                    kind: "app",
                    title: name,
                    subtitle: "Application",
                    preview: nil
                ))
                if result.count >= limit { break }
            }
            if result.count >= limit { break }
        }

        return result.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func run(id: String, kind: String) {
        switch kind {
        case "app":
            NSWorkspace.shared.open(URL(fileURLWithPath: String(id.dropFirst(4))))
        case "file":
            NSWorkspace.shared.open(URL(fileURLWithPath: String(id.dropFirst(5))))
        case "calculator":
            let value = String(id.dropFirst(5))
            ClipboardStore.shared.suppressNextCapture()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        case "emoji":
            let glyph = String(id.dropFirst(6))
            guard !glyph.isEmpty else { return }
            PasteHelper.captureFrontApp()
            PasteHelper.pasteTextDirect(glyph)
        case "clipboard":
            if id == "cmd.clipboard.clear" {
                ClipboardStore.shared.clear()
                return
            }
            ClipboardStore.shared.paste(String(id.dropFirst(5)))
        case "snippet":
            let sid = String(id.dropFirst(5))
            if let s = SnippetStore.shared.allEnabledSnippets.first(where: { $0.id == sid }) {
                PasteHelper.captureFrontApp()
                SnippetStore.shared.pasteSnippet(s)
            }
        case "quicklink":
            // id = qlink:<id>:<remainder>
            let rest = String(id.dropFirst(6))
            if let colon = rest.firstIndex(of: ":") {
                let qid = String(rest[..<colon])
                let query = String(rest[rest.index(after: colon)...])
                QuicklinkStore.shared.open(qid, query: query)
            } else {
                QuicklinkStore.shared.open(rest, query: "")
            }
        case "script":
            ScriptCommandStore.shared.run(String(id.dropFirst(7)))
        case "extension":
            ExtensionStore.shared.run(id: id)
        case "window":
            let snap: WindowManager.Snap?
            switch id {
            case "win:left": snap = .leftHalf
            case "win:right": snap = .rightHalf
            case "win:top": snap = .topHalf
            case "win:bottom": snap = .bottomHalf
            case "win:tl": snap = .topLeft
            case "win:tr": snap = .topRight
            case "win:bl": snap = .bottomLeft
            case "win:br": snap = .bottomRight
            case "win:max": snap = .maximize
            case "win:center": snap = .center
            default: snap = nil
            }
            if let snap { _ = WindowManager.snap(snap) }
        case "command":
            switch id {
            case "cmd.settings":
                openSettingsHandler?()
            case "cmd.snippets":
                NotificationCenter.default.post(name: .blitzOpenSnippets, object: nil)
            case "cmd.clipboard":
                NotificationCenter.default.post(name: .blitzShowClipboard, object: nil)
            case "cmd.clipboard.clear":
                ClipboardStore.shared.clear()
            case "cmd.quicklinks":
                NotificationCenter.default.post(name: .blitzOpenCatalogs, object: nil, userInfo: ["scripts": false])
            case "cmd.scripts":
                NotificationCenter.default.post(name: .blitzOpenCatalogs, object: nil, userInfo: ["scripts": true])
            case "cmd.extensions":
                ExtensionStore.shared.openExtensionsFolder()
            case "cmd.extensions.reload":
                ExtensionStore.shared.load()
            case "cmd.emoji":
                // Hint only — user types in launcher; show a few defaults by posting nothing.
                break
            default:
                break
            }
        default:
            break
        }
    }
}
