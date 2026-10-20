import Foundation
import SQLite3

/// SQLite persistence for clipboard history and snippets.
/// Path: ~/Library/Application Support/Blitz/blitz.sqlite
final class BlitzDatabase {
    static let shared = BlitzDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "research.reversedir.blitz.db", qos: .utility)

    /// Application Support folder for Blitz.
    static var supportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Blitz", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var dbURL: URL {
        Self.supportDirectory.appendingPathComponent("blitz.sqlite")
    }

    private init() {
        open()
        migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func open() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            FileLogger.log("db: open failed \(dbURL.path)")
            db = nil
            return
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA foreign_keys=ON;")
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            text TEXT NOT NULL,
            image_file_name TEXT,
            payload_file_name TEXT,
            created_at REAL NOT NULL,
            ocr_text TEXT,
            content_hash TEXT,
            position INTEGER NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0
        );
        """)
        if !clipboardHasColumn("pinned") {
            exec("ALTER TABLE clipboard_items ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;")
        }
        exec("CREATE INDEX IF NOT EXISTS idx_clip_position ON clipboard_items(position);")
        exec("CREATE INDEX IF NOT EXISTS idx_clip_hash ON clipboard_items(content_hash);")

        exec("""
        CREATE TABLE IF NOT EXISTS snippet_folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            hotkey_code INTEGER,
            hotkey_modifiers INTEGER,
            position INTEGER NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS snippets (
            id TEXT PRIMARY KEY,
            folder_id TEXT NOT NULL,
            keyword TEXT NOT NULL,
            content TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            position INTEGER NOT NULL,
            FOREIGN KEY(folder_id) REFERENCES snippet_folders(id) ON DELETE CASCADE
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_snip_folder ON snippets(folder_id);")

        exec("""
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        guard let db else { return false }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            FileLogger.log("db: exec error \(msg)")
            return false
        }
        return true
    }

    private func meta(_ key: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    private func setMeta(_ key: String, _ value: String) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO meta(key,value) VALUES(?,?);", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Clipboard

    func loadClipboard() -> [ClipboardItem] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            SELECT id, kind, text, image_file_name, payload_file_name, created_at, ocr_text, content_hash, pinned
            FROM clipboard_items ORDER BY pinned DESC, position ASC;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var out: [ClipboardItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let kindRaw = String(cString: sqlite3_column_text(stmt, 1))
                let text = String(cString: sqlite3_column_text(stmt, 2))
                let image = optionalColumnText(stmt, 3)
                let payload = optionalColumnText(stmt, 4)
                let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                let ocr = optionalColumnText(stmt, 6)
                let hash = optionalColumnText(stmt, 7)
                let pinned = sqlite3_column_int(stmt, 8) != 0
                let kind = ClipboardKind(rawValue: kindRaw) ?? .text
                out.append(ClipboardItem(
                    id: id, kind: kind, text: text,
                    imageFileName: image, payloadFileName: payload,
                    createdAt: created, ocrText: ocr, contentHash: hash,
                    pinned: pinned
                ))
            }
            return out
        }
    }

    func replaceClipboard(_ items: [ClipboardItem]) {
        queue.sync {
            guard let db else { return }
            exec("BEGIN;")
            exec("DELETE FROM clipboard_items;")
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO clipboard_items
            (id, kind, text, image_file_name, payload_file_name, created_at, ocr_text, content_hash, position, pinned)
            VALUES (?,?,?,?,?,?,?,?,?,?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                exec("ROLLBACK;")
                return
            }
            defer { sqlite3_finalize(stmt) }
            for (i, item) in items.enumerated() {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, item.text, -1, SQLITE_TRANSIENT)
                bindOptionalText(stmt, 4, item.imageFileName)
                bindOptionalText(stmt, 5, item.payloadFileName)
                sqlite3_bind_double(stmt, 6, item.createdAt.timeIntervalSince1970)
                bindOptionalText(stmt, 7, item.ocrText)
                bindOptionalText(stmt, 8, item.contentHash)
                sqlite3_bind_int(stmt, 9, Int32(i))
                sqlite3_bind_int(stmt, 10, item.pinned ? 1 : 0)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    FileLogger.log("db: insert clip failed")
                }
            }
            exec("COMMIT;")
        }
    }

    func updateClipboardOCR(id: String, ocr: String) {
        queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET ocr_text=? WHERE id=?;", -1, &stmt, nil) == SQLITE_OK else {
                return
            }
            sqlite3_bind_text(stmt, 1, ocr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
    }

    /// One-time import from legacy clipboard.json if DB empty.
    func migrateClipboardJSONIfNeeded(jsonURL: URL, mediaDir: URL) {
        let already: Bool = queue.sync { meta("clipboard_migrated") == "1" || clipboardCount() > 0 }
        if already {
            queue.sync { setMeta("clipboard_migrated", "1") }
            return
        }
        guard let data = try? Data(contentsOf: jsonURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data),
              !decoded.isEmpty else {
            queue.sync { setMeta("clipboard_migrated", "1") }
            return
        }
        let filtered = decoded.filter { item in
            if let name = item.imageFileName {
                return FileManager.default.fileExists(atPath: mediaDir.appendingPathComponent(name).path)
            }
            if let name = item.payloadFileName {
                return FileManager.default.fileExists(atPath: mediaDir.appendingPathComponent(name).path)
            }
            return true
        }
        replaceClipboard(filtered)
        queue.sync { setMeta("clipboard_migrated", "1") }
        FileLogger.log("db: migrated \(filtered.count) clipboard items from JSON")
    }

    private func clipboardCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clipboard_items;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func clipboardHasColumn(_ name: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(clipboard_items);", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == name {
                return true
            }
        }
        return false
    }

    // MARK: - Snippets

    func loadFolders() -> [SnippetFolder] {
        queue.sync {
            guard let db else { return [] }
            var folderStmt: OpaquePointer?
            defer { sqlite3_finalize(folderStmt) }
            let fsql = """
            SELECT id, name, hotkey_code, hotkey_modifiers, position
            FROM snippet_folders ORDER BY position ASC;
            """
            guard sqlite3_prepare_v2(db, fsql, -1, &folderStmt, nil) == SQLITE_OK else { return [] }

            var folders: [SnippetFolder] = []
            while sqlite3_step(folderStmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(folderStmt, 0))
                let name = String(cString: sqlite3_column_text(folderStmt, 1))
                let code: UInt32? = sqlite3_column_type(folderStmt, 2) == SQLITE_NULL
                    ? nil : UInt32(bitPattern: sqlite3_column_int(folderStmt, 2))
                let mods: UInt32? = sqlite3_column_type(folderStmt, 3) == SQLITE_NULL
                    ? nil : UInt32(bitPattern: sqlite3_column_int(folderStmt, 3))

                var snipStmt: OpaquePointer?
                let ssql = """
                SELECT id, keyword, content, enabled, position
                FROM snippets WHERE folder_id=? ORDER BY position ASC;
                """
                var snippets: [Snippet] = []
                if sqlite3_prepare_v2(db, ssql, -1, &snipStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(snipStmt, 1, id, -1, SQLITE_TRANSIENT)
                    while sqlite3_step(snipStmt) == SQLITE_ROW {
                        let sid = String(cString: sqlite3_column_text(snipStmt, 0))
                        let keyword = String(cString: sqlite3_column_text(snipStmt, 1))
                        let content = String(cString: sqlite3_column_text(snipStmt, 2))
                        let enabled = sqlite3_column_int(snipStmt, 3) != 0
                        snippets.append(Snippet(
                            id: sid, keyword: keyword, content: content,
                            enabled: enabled, folderId: id
                        ))
                    }
                }
                sqlite3_finalize(snipStmt)

                folders.append(SnippetFolder(
                    id: id, name: name, snippets: snippets,
                    hotKeyCode: code, hotKeyModifiers: mods
                ))
            }
            return folders
        }
    }

    func replaceFolders(_ folders: [SnippetFolder]) {
        queue.sync {
            guard db != nil else { return }
            exec("BEGIN;")
            exec("DELETE FROM snippets;")
            exec("DELETE FROM snippet_folders;")

            var fstmt: OpaquePointer?
            var sstmt: OpaquePointer?
            defer {
                sqlite3_finalize(fstmt)
                sqlite3_finalize(sstmt)
            }
            let fsql = """
            INSERT INTO snippet_folders(id, name, hotkey_code, hotkey_modifiers, position)
            VALUES (?,?,?,?,?);
            """
            let ssql = """
            INSERT INTO snippets(id, folder_id, keyword, content, enabled, position)
            VALUES (?,?,?,?,?,?);
            """
            guard let db,
                  sqlite3_prepare_v2(db, fsql, -1, &fstmt, nil) == SQLITE_OK,
                  sqlite3_prepare_v2(db, ssql, -1, &sstmt, nil) == SQLITE_OK else {
                exec("ROLLBACK;")
                return
            }

            for (fi, folder) in folders.enumerated() {
                sqlite3_reset(fstmt)
                sqlite3_clear_bindings(fstmt)
                sqlite3_bind_text(fstmt, 1, folder.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(fstmt, 2, folder.name, -1, SQLITE_TRANSIENT)
                if let c = folder.hotKeyCode {
                    sqlite3_bind_int(fstmt, 3, Int32(bitPattern: c))
                } else {
                    sqlite3_bind_null(fstmt, 3)
                }
                if let m = folder.hotKeyModifiers {
                    sqlite3_bind_int(fstmt, 4, Int32(bitPattern: m))
                } else {
                    sqlite3_bind_null(fstmt, 4)
                }
                sqlite3_bind_int(fstmt, 5, Int32(fi))
                _ = sqlite3_step(fstmt)

                for (si, snip) in folder.snippets.enumerated() {
                    sqlite3_reset(sstmt)
                    sqlite3_clear_bindings(sstmt)
                    sqlite3_bind_text(sstmt, 1, snip.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(sstmt, 2, folder.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(sstmt, 3, snip.keyword, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(sstmt, 4, snip.content, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(sstmt, 5, snip.enabled ? 1 : 0)
                    sqlite3_bind_int(sstmt, 6, Int32(si))
                    _ = sqlite3_step(sstmt)
                }
            }
            exec("COMMIT;")
        }
    }

    func migrateSnippetsJSONIfNeeded(jsonURL: URL) {
        let already: Bool = queue.sync { meta("snippets_migrated") == "1" || folderCount() > 0 }
        if already {
            queue.sync { setMeta("snippets_migrated", "1") }
            return
        }
        guard let data = try? Data(contentsOf: jsonURL) else {
            queue.sync { setMeta("snippets_migrated", "1") }
            return
        }
        var folders: [SnippetFolder] = []
        if let decoded = try? JSONDecoder().decode([SnippetFolder].self, from: data), !decoded.isEmpty {
            folders = decoded
        } else if let flat = try? JSONDecoder().decode([LegacySnippetRow].self, from: data), !flat.isEmpty {
            let fid = UUID().uuidString
            folders = [SnippetFolder(
                id: fid,
                name: "General",
                snippets: flat.map {
                    Snippet(id: $0.id, keyword: $0.keyword, content: $0.content, folderId: fid)
                }
            )]
        }
        if !folders.isEmpty {
            replaceFolders(folders)
            FileLogger.log("db: migrated \(folders.count) snippet folders from JSON")
        }
        queue.sync { setMeta("snippets_migrated", "1") }
    }

    private func folderCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM snippet_folders;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private struct LegacySnippetRow: Codable {
        var id: String
        var keyword: String
        var content: String
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func optionalColumnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }
}

/// SQLite wants a destructor pointer; use transient copy for Swift strings.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
