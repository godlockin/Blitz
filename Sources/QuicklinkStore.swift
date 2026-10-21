import AppKit

struct Quicklink: Codable, Identifiable {
    var id: String
    var name: String
    var url: String
}

final class QuicklinkStore {
    static let shared = QuicklinkStore()
    private(set) var items: [Quicklink] = []

    private var storeURL: URL {
        BlitzDatabase.supportDirectory.appendingPathComponent("quicklinks.json")
    }

    func load() {
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([Quicklink].self, from: data),
           !decoded.isEmpty {
            items = decoded
        } else {
            items = [
                Quicklink(id: "1", name: "GitHub", url: "https://github.com"),
                Quicklink(id: "2", name: "Google", url: "https://www.google.com/search?q={Query}")
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
    func add(name: String, url: String) -> String {
        let id = UUID().uuidString
        items.append(Quicklink(id: id, name: name, url: url))
        save()
        return id
    }

    func update(id: String, name: String, url: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].name = name
        items[i].url = url
        save()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func open(_ id: String, query: String) {
        guard let link = items.first(where: { $0.id == id }) else { return }
        var urlString = link.url
        if urlString.contains("{Query}") {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            urlString = urlString.replacingOccurrences(of: "{Query}", with: encoded)
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
