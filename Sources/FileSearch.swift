import Foundation

enum FileSearch {
    struct Ranked {
        let item: SearchItem
        let score: Int
    }

    /// Fast filename search via `fd` / `rg`, with shallow + mdfind fallback.
    /// Must NOT be called on the main thread for long queries.
    static func search(query: String, limit: Int = 40) -> [SearchItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { return [] }

        var ranked: [Ranked] = []
        var seen = Set<String>()

        // 1) fd (fastest) — filename regex / glob
        if let fd = ToolPath.fd {
            for path in runFd(fd, query: q, limit: limit * 3) {
                append(path: path, query: q, seen: &seen, ranked: &ranked)
            }
        }

        // 2) rg --files with glob (if still need more, or fd missing)
        if ranked.count < limit, let rg = ToolPath.rg {
            for path in runRgFiles(rg, query: q, limit: limit * 2) {
                append(path: path, query: q, seen: &seen, ranked: &ranked)
                if ranked.count >= limit { break }
            }
        }

        // 3) Shallow local scan (always cheap, fills gaps)
        if ranked.count < limit {
            for path in shallowScan(query: q, limit: limit) {
                append(path: path, query: q, seen: &seen, ranked: &ranked)
                if ranked.count >= limit { break }
            }
        }

        // 4) Spotlight last resort
        if ranked.count < max(8, limit / 2), ToolPath.fd == nil {
            for path in mdfindFast(query: q, limit: limit) {
                append(path: path, query: q, seen: &seen, ranked: &ranked)
                if ranked.count >= limit { break }
            }
        }

        return ranked
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.item)
    }

    private static func append(path: String, query: String, seen: inout Set<String>, ranked: inout [Ranked]) {
        if seen.contains(path) { return }
        seen.insert(path)
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard let score = matchScore(fileName: name, query: query) else { return }
        ranked.append(Ranked(
            item: SearchItem(
                id: "file:" + path,
                kind: "file",
                title: name,
                subtitle: url.deletingLastPathComponent().path,
                preview: nil
            ),
            score: score
        ))
    }

    /// 200 = exact, 150 = prefix, 100 = contains (word boundary), 50 = contains
    static func matchScore(fileName: String, query: String) -> Int? {
        let name = fileName as NSString
        let q = query as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if name.compare(q as String, options: options) == .orderedSame { return 200 }
        if name.range(of: q as String, options: options.union(.anchored)).location != NSNotFound {
            return 150
        }
        let stem = (fileName as NSString).deletingPathExtension
        if (stem as NSString).range(of: q as String, options: options.union(.anchored)).location != NSNotFound {
            return 140
        }
        let range = name.range(of: q as String, options: options)
        guard range.location != NSNotFound else { return nil }
        if range.location == 0 { return 150 }
        let before = name.substring(to: range.location)
        if before.last == " " || before.last == "-" || before.last == "_" || before.last == "." {
            return 100
        }
        return 50
    }

    // MARK: - fd / rg

    private static var searchRoots: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            home + "/Desktop",
            home + "/Downloads",
            home + "/Documents",
            home + "/Projects",
            home + "/Developer",
            home + "/working",
            home + "/code",
            home + "/src",
            home
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// `fd -ig '*query*' roots` — filename glob, with excludes + timeout.
    private static func runFd(_ fd: String, query: String, limit: Int) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Search focused roots first (no full-home walk — too slow / noisy).
        var roots = searchRoots.filter { $0 != home }
        if roots.isEmpty { roots = [home] }

        let globPattern = "*\(escapeGlob(query))*"
        var args = [
            "--color=never",
            "--ignore-case",
            "--glob",
            "--exclude", ".git",
            "--exclude", "node_modules",
            "--exclude", "Library",
            "--exclude", ".Trash",
            "--exclude", "DerivedData",
            "--exclude", "Caches",
            "--exclude", ".cache",
            "--exclude", "vendor",
            "--exclude", ".npm",
            "--exclude", "dist",
            "--exclude", "build",
            "--max-results", "\(limit)",
            "--",
            globPattern
        ]
        args.append(contentsOf: roots)
        return runProcess(executable: fd, arguments: args, timeout: 0.65)
    }

    /// `rg --files -g '*query*'` over key roots (filename glob filter).
    private static func runRgFiles(_ rg: String, query: String, limit: Int) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = searchRoots.filter { $0 != home } // avoid full-home with rg --files
        guard !roots.isEmpty else { return [] }
        let glob = "*\(escapeGlob(query))*"
        var args = [
            "--files",
            "--color", "never",
            "--glob", glob,
            "--glob", "!.git/**",
            "--glob", "!node_modules/**",
            "--glob", "!Library/**",
            "--glob", "!**/DerivedData/**"
        ]
        args.append(contentsOf: roots)
        let lines = runProcess(executable: rg, arguments: args, timeout: 0.5)
        return Array(lines.prefix(limit))
    }

    private static func escapeGlob(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "?", with: "\\?")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
    }

    private static func runProcess(executable: String, arguments: [String], timeout: TimeInterval) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        // Ensure Homebrew tools are found if somehow invoked without full path
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin"
        if !path.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + path
        }
        task.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return []
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            task.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            _ = group.wait(timeout: .now() + 0.15)
            // Still read whatever was produced
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - Fallback

    private static func shallowScan(query: String, limit: Int) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Desktop", "Downloads", "Documents"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
        var out: [String] = []
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(0.25)

        for root in roots {
            guard out.count < limit, Date() < deadline else { break }
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries {
                guard out.count < limit, Date() < deadline else { break }
                if matchScore(fileName: url.lastPathComponent, query: query) != nil {
                    out.append(url.path)
                }
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let kids = try? fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) {
                        for kid in kids.prefix(60) {
                            guard out.count < limit, Date() < deadline else { break }
                            if matchScore(fileName: kid.lastPathComponent, query: query) != nil {
                                out.append(kid.path)
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    private static func mdfindFast(query: String, limit: Int) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let scopes = [home + "/Documents", home + "/Downloads", home + "/Desktop"]
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let pred = "kMDItemFSName == \"\(escaped)*\"cdw"

        var paths: [String] = []
        for scope in scopes {
            guard paths.count < limit else { break }
            let lines = runProcess(
                executable: "/usr/bin/mdfind",
                arguments: ["-onlyin", scope, pred],
                timeout: 0.4
            )
            for p in lines {
                paths.append(p)
                if paths.count >= limit { return paths }
            }
        }
        return paths
    }
}

/// Resolve `fd` / `rg` once (Homebrew + common paths).
enum ToolPath {
    static let fd: String? = resolve(["fd", "fdfind"])
    static let rg: String? = resolve(["rg"])

    private static func resolve(_ names: [String]) -> String? {
        let extras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            NSHomeDirectory() + "/.cargo/bin",
            NSHomeDirectory() + "/.local/bin"
        ]
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = extras + pathEnv.split(separator: ":").map(String.init)
        let fm = FileManager.default
        for name in names {
            for dir in dirs {
                let candidate = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        // `which` fallback
        for name in names {
            let lines = FileSearch_which(name)
            if let first = lines.first, fm.isExecutableFile(atPath: first) {
                return first
            }
        }
        return nil
    }
}

private func FileSearch_which(_ name: String) -> [String] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    task.arguments = ["-a", name]
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
    task.environment = env
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do { try task.run() } catch { return [] }
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    return text.split(separator: "\n").map(String.init)
}
