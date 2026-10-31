import Foundation

/// Sleeve used to be called Afterglow. On the first launch under the new name, moves the
/// old app's data across (settings, wallpaper library, lyrics cache) so nothing is lost.
public enum LegacyAppData {
    public static let legacyName = "Afterglow"

    public static func migrateIfNeeded(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldSupport = support.appendingPathComponent(legacyName, isDirectory: true)
        let newSupport = support.appendingPathComponent("Sleeve", isDirectory: true)
        if move(oldSupport, to: newSupport, fileManager: fileManager) {
            // The screensaver's pointer to the wallpaper video is an absolute path.
            let pointer = newSupport.appendingPathComponent("Wallpaper/screensaver-video.txt")
            if let path = try? String(contentsOf: pointer, encoding: .utf8) {
                let fixed = path.replacingOccurrences(of: oldSupport.path + "/", with: newSupport.path + "/")
                try? fixed.write(to: pointer, atomically: true, encoding: .utf8)
            }
        }
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        move(caches.appendingPathComponent("app.afterglow", isDirectory: true),
             to: caches.appendingPathComponent("app.sleeve", isDirectory: true), fileManager: fileManager)
    }

    /// Moves `old` to `new` only when there's something to move and nothing in the way.
    @discardableResult
    static func move(_ old: URL, to new: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return false }
        do {
            try fileManager.moveItem(at: old, to: new)
            return true
        } catch {
            NSLog("Sleeve: couldn't move \(old.path) to \(new.path): \(error)")
            return false
        }
    }
}
