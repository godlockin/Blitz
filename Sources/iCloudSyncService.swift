import Foundation

/// Sync catalogs via the user's **iCloud Drive** folder (CloudDocs).
/// Works without a paid Apple Developer iCloud container: writes to
/// `~/Library/Mobile Documents/com~apple~CloudDocs/Blitz/` when iCloud Drive is on.
final class iCloudSyncService {
    static let shared = iCloudSyncService()

    private var timer: Timer?
    private let queue = DispatchQueue(label: "research.reversedir.blitz.icloud", qos: .utility)

    private var cloudRoot: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Blitz", isDirectory: true)
        // Presence of CloudDocs parent ≈ iCloud Drive enabled for this user.
        let parent = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }

    var isAvailable: Bool { cloudRoot != nil }

    var statusMessage: String {
        guard SettingsStore.shared.iCloudSyncEnabled else { return "iCloud sync: off" }
        guard let root = cloudRoot else { return "iCloud sync: iCloud Drive not available" }
        return "iCloud sync: \(root.path)"
    }

    func start() {
        timer?.invalidate()
        guard SettingsStore.shared.iCloudSyncEnabled else { return }
        pushNow()
        pullNow()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.pullNow()
            self?.pushNow()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pushNow() {
        guard SettingsStore.shared.iCloudSyncEnabled, let root = cloudRoot else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let local = BlitzDatabase.supportDirectory
            let names = ["quicklinks.json", "scripts.json", "snippets.json"]
            for name in names {
                let src = local.appendingPathComponent(name)
                let dst = root.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                self.copyIfNewer(from: src, to: dst)
            }
            if SettingsStore.shared.iCloudSyncClipboardText {
                self.pushClipboardTextIndex(to: root)
            }
            FileLogger.log("icloud: push → \(root.path)")
        }
    }

    func pullNow() {
        guard SettingsStore.shared.iCloudSyncEnabled, let root = cloudRoot else { return }
        queue.async {
            let local = BlitzDatabase.supportDirectory
            let pairs = [
                ("quicklinks.json", { QuicklinkStore.shared.load() }),
                ("scripts.json", { ScriptCommandStore.shared.load() }),
                ("snippets.json", { SnippetStore.shared.reloadFromDiskJSON() })
            ]
            for (name, reload) in pairs {
                let src = root.appendingPathComponent(name)
                let dst = local.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                if self.copyIfNewer(from: src, to: dst) {
                    DispatchQueue.main.async { reload() }
                }
            }
        }
    }

    @discardableResult
    private func copyIfNewer(from src: URL, to dst: URL) -> Bool {
        let fm = FileManager.default
        guard let srcVals = try? src.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let srcDate = srcVals.contentModificationDate else { return false }
        if let dstVals = try? dst.resourceValues(forKeys: [.contentModificationDateKey]),
           let dstDate = dstVals.contentModificationDate,
           dstDate >= srcDate {
            return false
        }
        try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        do {
            try fm.copyItem(at: src, to: dst)
            return true
        } catch {
            FileLogger.log("icloud: copy failed \(src.lastPathComponent): \(error)")
            return false
        }
    }

    private func pushClipboardTextIndex(to root: URL) {
        struct Row: Codable {
            let id: String
            let kind: String
            let text: String
            let pinned: Bool
            let createdAt: TimeInterval
        }
        let rows = ClipboardStore.shared.items.compactMap { item -> Row? in
            guard item.kind == .text || item.kind == .url || item.kind == .color else { return nil }
            return Row(
                id: item.id,
                kind: item.kind.rawValue,
                text: String(item.text.prefix(4000)),
                pinned: item.pinned,
                createdAt: item.createdAt.timeIntervalSince1970
            )
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        let dst = root.appendingPathComponent("clipboard-text.json")
        try? data.write(to: dst, options: .atomic)
    }
}
