import Foundation

/// Installs the bundled "Sleeve" screensaver (plays the current wallpaper video) and
/// selects it, remembering the previous screensaver so it can be put back.
enum ScreenSaverInstaller {
    /// Set once at launch to the wallpaper data folder.
    nonisolated(unsafe) static var root = WallpaperLibrary.defaultRoot

    private static var fileManager: FileManager { .default }

    static var bundled: URL? {
        Bundle.main.url(forResource: "Sleeve", withExtension: "saver")
    }

    static var installed: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Sleeve.saver", isDirectory: true)
    }

    /// Where the app installed it when it was called Afterglow.
    private static var legacyInstalled: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Afterglow.saver", isDirectory: true)
    }

    /// Replaces the screensaver installed under the app's old name with this one, keeping
    /// it selected and keeping the user's previous screensaver remembered.
    static var hasLegacy: Bool { fileManager.fileExists(atPath: legacyInstalled.path) }

    static func migrateLegacy() {
        guard fileManager.fileExists(atPath: legacyInstalled.path) else { return }
        try? install()
        try? fileManager.removeItem(at: legacyInstalled)
    }

    private static var originalsURL: URL {
        root.appendingPathComponent("screensaver-originals.plist")
    }

    static var isInstalled: Bool {
        fileManager.fileExists(atPath: installed.path)
    }

    private static var pointerURL: URL {
        root.appendingPathComponent("screensaver-video.txt")
    }

    static func install() throws {
        guard let bundled else { throw CocoaError(.fileNoSuchFile) }
        try fileManager.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        if isInstalled { try fileManager.removeItem(at: installed) }
        try fileManager.copyItem(at: bundled, to: installed)
        select()
    }

    static func remove() {
        unselect()
        try? fileManager.removeItem(at: installed)
    }

    static func refreshIfInstalled() {
        guard isInstalled, let bundled else { return }
        let executable = "Contents/MacOS/SleeveSaver"
        let current = try? Data(contentsOf: installed.appendingPathComponent(executable))
        let shipped = try? Data(contentsOf: bundled.appendingPathComponent(executable))
        guard let shipped, current != shipped else { return }
        try? fileManager.removeItem(at: installed)
        try? fileManager.copyItem(at: bundled, to: installed)
        let host = Process()
        host.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        host.arguments = ["legacyScreenSaver"]
        try? host.run()
        host.waitUntilExit()
    }

    static func select() {
        guard let store = WallpaperStore.read(),
              let configuration = try? PropertyListSerialization.data(
                  fromPropertyList: ["module": ["relative": installed.absoluteString]], format: .binary, options: 0) else { return }
        let ours: [String: Any] = [
            "Choices": [["Configuration": configuration, "Files": [Any](), "Provider": "com.apple.wallpaper.choice.screen-saver"]],
            "Shuffle": "$null",
        ]
        var saved = WallpaperStore.readPlist(originalsURL) as? [String: Any] ?? [:]
        var changed = false
        let updated = WallpaperStore.replacingContents(in: store, changed: &changed) { path, content in
            guard path.hasSuffix("/Idle/Content"), !isCurrent(content) else { return nil }
            if saved[path] == nil, !isOurs(content) { saved[path] = content }
            return ours
        }
        WallpaperStore.writePlist(saved, to: originalsURL)
        if changed, let updated = updated as? [String: Any], WallpaperStore.write(updated) {
            WallpaperStore.reloadAgent()
        }
    }

    static func unselect() {
        defer { try? fileManager.removeItem(at: originalsURL) }
        guard let saved = WallpaperStore.readPlist(originalsURL) as? [String: Any], let fallback = saved.values.first,
              let store = WallpaperStore.read() else { return }
        var changed = false
        let restored = WallpaperStore.replacingContents(in: store, changed: &changed) { path, content in
            path.hasSuffix("/Idle/Content") && isOurs(content) ? (saved[path] ?? fallback) : nil
        }
        if changed, let restored = restored as? [String: Any], WallpaperStore.write(restored) {
            WallpaperStore.reloadAgent()
        }
    }

    private static func isCurrent(_ content: [String: Any]) -> Bool {
        WallpaperStore.content(content, references: "Screen%20Savers/Sleeve.saver")
    }

    /// This screensaver, under its current or its old name.
    private static func isOurs(_ content: [String: Any]) -> Bool {
        isCurrent(content) || WallpaperStore.content(content, references: "Screen%20Savers/Afterglow.saver")
    }

    static func sync(video: URL?) async {
        await Task.detached(priority: .utility) {
            if let video {
                try? fileManager.createDirectory(at: pointerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? video.path.write(to: pointerURL, atomically: true, encoding: .utf8)
            } else {
                try? fileManager.removeItem(at: pointerURL)
            }
        }.value
    }
}
