import Foundation

enum WallpaperStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    static func read() -> [String: Any]? {
        readPlist(url) as? [String: Any]
    }

    static func write(_ store: [String: Any]) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func reloadAgent() {
        let agent = Process()
        agent.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        agent.arguments = ["-KILL", "WallpaperAgent"]
        try? agent.run()
        agent.waitUntilExit()
    }

    static func forEachContent(in value: Any, path: String = "", _ visit: (String, [String: Any]) -> Void) {
        guard let dict = value as? [String: Any] else { return }
        for (key, child) in dict {
            let childPath = path + "/" + key
            if key == "Content", let content = child as? [String: Any] {
                visit(childPath, content)
            } else {
                forEachContent(in: child, path: childPath, visit)
            }
        }
    }

    static func replacingContents(in value: Any, path: String = "", changed: inout Bool,
                                  _ transform: (String, [String: Any]) -> Any?) -> Any {
        guard var dict = value as? [String: Any] else { return value }
        for (key, child) in dict {
            let childPath = path + "/" + key
            if key == "Content", let content = child as? [String: Any] {
                if let replacement = transform(childPath, content) {
                    dict[key] = replacement
                    changed = true
                }
            } else {
                dict[key] = replacingContents(in: child, path: childPath, changed: &changed, transform)
            }
        }
        return dict
    }

    static func content(_ content: [String: Any], references marker: String) -> Bool {
        let bytes = Data(marker.utf8)
        let choices = content["Choices"] as? [[String: Any]] ?? []
        return choices.contains { ($0["Configuration"] as? Data)?.range(of: bytes) != nil }
    }

    static func readPlist(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    static func writePlist(_ value: Any, to url: URL) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
