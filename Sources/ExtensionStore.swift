import AppKit
import Foundation

/// Local extension ecosystem: drop-in folders under Application Support.
/// Each extension is `Extensions/<id>/extension.json` (+ optional scripts).
struct BlitzExtensionCommand: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    /// `run` = shell via zsh -lc; `open` = open URL / path
    var mode: String
    var command: String?
    var url: String?
}

struct BlitzExtensionManifest: Codable, Identifiable {
    var id: String
    var name: String
    var author: String?
    var commands: [BlitzExtensionCommand]
}

final class ExtensionStore {
    static let shared = ExtensionStore()

    private(set) var extensions: [BlitzExtensionManifest] = []

    var extensionsDirectory: URL {
        let dir = BlitzDatabase.supportDirectory.appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func load() {
        ensureSampleExtension()
        var loaded: [BlitzExtensionManifest] = []
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: extensionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            extensions = []
            return
        }
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let manifestURL = dir.appendingPathComponent("extension.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let decoded = try? JSONDecoder().decode(BlitzExtensionManifest.self, from: data) else {
                continue
            }
            loaded.append(decoded)
        }
        extensions = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        FileLogger.log("extensions: loaded \(extensions.count)")
    }

    func searchItems(matching q: String) -> [SearchItem] {
        var out: [SearchItem] = []
        for ext in extensions {
            for cmd in ext.commands {
                let hay = (cmd.title + " " + (cmd.subtitle ?? "") + " " + ext.name).lowercased()
                if !q.isEmpty, !hay.contains(q), !q.contains("ext"), !q.contains("扩展"), !q.contains("plugin") {
                    continue
                }
                out.append(SearchItem(
                    id: "ext:\(ext.id)/\(cmd.id)",
                    kind: "extension",
                    title: cmd.title,
                    subtitle: "Extension · \(ext.name)" + (cmd.subtitle.map { " · \($0)" } ?? ""),
                    preview: nil
                ))
            }
        }
        return out
    }

    func run(id: String) {
        // id = ext:<extId>/<cmdId>
        let rest = String(id.dropFirst(4))
        guard let slash = rest.firstIndex(of: "/") else { return }
        let extId = String(rest[..<slash])
        let cmdId = String(rest[rest.index(after: slash)...])
        guard let ext = extensions.first(where: { $0.id == extId }),
              let cmd = ext.commands.first(where: { $0.id == cmdId }) else { return }

        switch cmd.mode {
        case "open":
            if let urlStr = cmd.url, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            } else if let path = cmd.command {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        default:
            let shell = cmd.command ?? "true"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-lc", shell]
            task.currentDirectoryURL = extensionsDirectory.appendingPathComponent(extId)
            try? task.run()
        }
    }

    func openExtensionsFolder() {
        NSWorkspace.shared.open(extensionsDirectory)
    }

    private func ensureSampleExtension() {
        let id = "blitz.sample"
        let dir = extensionsDirectory.appendingPathComponent(id, isDirectory: true)
        let manifest = dir.appendingPathComponent("extension.json")
        if FileManager.default.fileExists(atPath: manifest.path) { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sample = BlitzExtensionManifest(
            id: id,
            name: "Blitz Sample",
            author: "Blitz",
            commands: [
                BlitzExtensionCommand(
                    id: "hello",
                    title: "Sample: Hello from Extension",
                    subtitle: "Runs a local echo",
                    mode: "run",
                    command: "osascript -e 'display notification \"Hello from Blitz extension\" with title \"Blitz\"'",
                    url: nil
                ),
                BlitzExtensionCommand(
                    id: "docs",
                    title: "Sample: Open Extensions Folder",
                    subtitle: "Reveal ~/Library/Application Support/Blitz/Extensions",
                    mode: "open",
                    command: extensionsDirectory.path,
                    url: nil
                )
            ]
        )
        if let data = try? JSONEncoder().encode(sample) {
            try? data.write(to: manifest, options: .atomic)
        }
        let readme = dir.appendingPathComponent("README.txt")
        let text = """
        Blitz local extension
        =====================
        Put extension.json in this folder. Commands appear in the launcher.

        mode: run   → zsh -lc <command>
        mode: open  → open <url> or <command as path>

        Reload: restart Blitz or search “extension”.
        """
        try? text.write(to: readme, atomically: true, encoding: .utf8)
    }
}
