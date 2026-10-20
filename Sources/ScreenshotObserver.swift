import AppKit

/// Watches Spotlight metadata for new screen captures and injects them into clipboard history.
final class ScreenshotObserver {
    static let shared = ScreenshotObserver()

    private var query: NSMetadataQuery?
    private var known = Set<String>()

    func start() {
        stop()
        guard SettingsStore.shared.observeScreenshots else { return }

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.predicate = NSPredicate(format: "%K == 1", "kMDItemIsScreenCapture")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryUpdated(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: q
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryUpdated(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )
        q.start()
        query = q
    }

    func stop() {
        query?.stop()
        query = nil
        NotificationCenter.default.removeObserver(self)
    }

    func restart() {
        stop()
        start()
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if known.contains(path) { continue }
            known.insert(path)
            // Skip initial flood — only accept files modified in the last 15s.
            if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]),
               let mod = values.contentModificationDate,
               Date().timeIntervalSince(mod) > 15 {
                continue
            }
            guard let image = NSImage(contentsOfFile: path) else { continue }
            ClipboardStore.shared.ingestScreenshot(image, sourcePath: path)
        }
        if known.count > 400 {
            known = Set(known.suffix(200))
        }
    }
}
