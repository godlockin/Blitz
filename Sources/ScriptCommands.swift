import Foundation
import AppKit

struct ScriptCommand: Codable, Identifiable {
    var id: String
    var title: String
    var command: String
}

final class ScriptCommandStore {
    static let shared = ScriptCommandStore()
    private(set) var items: [ScriptCommand] = []

    private var storeURL: URL {
        BlitzDatabase.supportDirectory.appendingPathComponent("scripts.json")
    }

    func load() {
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([ScriptCommand].self, from: data),
           !decoded.isEmpty {
            items = decoded
        } else {
            items = [
                ScriptCommand(id: "1", title: "Open Home in Terminal", command: "open -a Terminal \"$HOME\""),
                ScriptCommand(id: "2", title: "Copy UTC Date", command: "date -u \"+%Y-%m-%dT%H:%M:%SZ\" | pbcopy")
            ]
            save()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
        iCloudSyncService.shared.pushNow()
    }

    @discardableResult
    func add(title: String, command: String) -> String {
        let id = UUID().uuidString
        items.append(ScriptCommand(id: id, title: title, command: command))
        save()
        return id
    }

    func update(id: String, title: String, command: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = title
        items[i].command = command
        save()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func run(_ id: String) {
        guard let script = items.first(where: { $0.id == id }) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", script.command]
        try? task.run()
    }
}
