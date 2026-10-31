import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Sets the system desktop picture (which macOS also shows on the lock screen and tints
/// the menu bar with) and restores the user's own picture afterwards.
///
/// The original picture and the wallpaper store entries are snapshotted before the first
/// change and restored on `restore()`; the snapshot survives a crash, so the next launch
/// can restore it too.
@MainActor
final class DesktopPicture {
    private struct Original: Codable {
        let displayID: UInt32
        let path: String
        let backupName: String?
        let scaling: Int?
        let allowClipping: Bool?
        let fillColor: [Double]?
    }

    private let fileManager = FileManager.default
    private let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("original.json") }
    private var framesDirectory: URL { directory.appendingPathComponent("Frames", isDirectory: true) }
    private var storeOriginalsURL: URL { directory.appendingPathComponent("store-originals.plist") }
    private var currentFrame: URL?

    init(directory: URL) {
        self.directory = directory
    }

    var hasSavedOriginal: Bool { fileManager.fileExists(atPath: stateURL.path) }
    /// Where callers write images to show; anything here counts as "ours" on restore.
    var imagesDirectory: URL { framesDirectory }

    /// Shows a still frame of the video.
    func mirror(_ video: URL) async {
        do {
            show(try await Self.exportFrame(from: video, into: framesDirectory))
        } catch {
            NSLog("Sleeve: couldn’t mirror frame to system wallpaper: \(error)")
        }
    }

    /// Shows an image that lives in `imagesDirectory`.
    func show(_ image: URL) {
        guard image != currentFrame else { return }
        snapshotOriginals()
        snapshotStore()
        currentFrame = image
        apply(image)
        removeFrames(except: image)
    }

    func screensChanged() {
        guard let currentFrame, hasSavedOriginal else { return }
        snapshotOriginals()
        snapshotStore()
        apply(currentFrame)
    }

    func spaceChanged() {
        guard let currentFrame, hasSavedOriginal else { return }
        snapshotStore()
        apply(currentFrame)
    }

    func restore() {
        defer {
            try? fileManager.removeItem(at: directory)
            currentFrame = nil
        }
        if restoreStore() { return }
        guard let originals = loadOriginals(), !originals.isEmpty else { return }
        for screen in NSScreen.screens {
            let original = originals.first { $0.displayID == screen.displayID } ?? originals[0]
            guard let url = resolvedURL(for: original) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options(for: original))
        }
    }

    private func snapshotStore() {
        guard let store = WallpaperStore.read() else { return }
        var saved = WallpaperStore.readPlist(storeOriginalsURL) as? [String: Any] ?? [:]
        let before = saved.count
        WallpaperStore.forEachContent(in: store) { path, content in
            if saved[path] == nil && !references(content) { saved[path] = content }
        }
        if saved.count != before { WallpaperStore.writePlist(saved, to: storeOriginalsURL) }
    }

    private func restoreStore() -> Bool {
        guard let saved = WallpaperStore.readPlist(storeOriginalsURL) as? [String: Any], let fallback = saved.values.first,
              let store = WallpaperStore.read() else { return false }
        var changed = false
        let restored = WallpaperStore.replacingContents(in: store, changed: &changed) { path, content in
            references(content) ? (saved[path] ?? fallback) : nil
        }
        guard changed else { return true }
        guard let restored = restored as? [String: Any], WallpaperStore.write(restored) else { return false }
        WallpaperStore.reloadAgent()
        return true
    }

    private func references(_ content: [String: Any]) -> Bool {
        WallpaperStore.content(content, references: framesDirectory.absoluteString)
    }

    private func apply(_ frame: URL) {
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(frame, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        }
    }

    /// The standalone LiveWallpaper app's state. While it runs, the desktop picture is
    /// its own still frame; the user's real picture is in its `original.json`.
    private static let legacyDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LiveWallpaper/SystemWallpaper", isDirectory: true)

    private func legacyOriginal(for displayID: UInt32) -> Original? {
        guard let data = try? Data(contentsOf: Self.legacyDirectory.appendingPathComponent("original.json")),
              let originals = try? JSONDecoder().decode([Original].self, from: data) else { return nil }
        guard let found = originals.first(where: { $0.displayID == displayID }) ?? originals.first else { return nil }
        // Keep a copy of its backup too, in case LiveWallpaper later deletes its folder.
        var backupName: String?
        if let legacyBackup = found.backupName {
            let name = "legacy-\(legacyBackup)"
            let target = directory.appendingPathComponent(name)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: target)
            if (try? fileManager.copyItem(at: Self.legacyDirectory.appendingPathComponent(legacyBackup), to: target)) != nil {
                backupName = name
            }
        }
        return Original(displayID: displayID, path: found.path, backupName: backupName,
                        scaling: found.scaling, allowClipping: found.allowClipping, fillColor: found.fillColor)
    }

    private func isLegacyFrame(_ path: String) -> Bool {
        path.hasPrefix(Self.legacyDirectory.appendingPathComponent("Frames").path)
    }

    /// Fixes originals recorded while LiveWallpaper was managing the desktop.
    func repairLegacyOriginals() {
        guard var originals = loadOriginals() else { return }
        var changed = false
        for (i, original) in originals.enumerated() where isLegacyFrame(original.path) {
            if let real = legacyOriginal(for: original.displayID) {
                originals[i] = real
                changed = true
            }
        }
        if changed, let data = try? JSONEncoder().encode(originals) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func snapshotOriginals() {
        var originals = loadOriginals() ?? []
        for screen in NSScreen.screens {
            guard let id = screen.displayID, !originals.contains(where: { $0.displayID == id }),
                  let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  !url.path.hasPrefix(directory.path) else { continue }
            if isLegacyFrame(url.path), let real = legacyOriginal(for: id) {
                originals.append(real)
                continue
            }

            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let backupName = "original-\(id).\(url.pathExtension.isEmpty ? "img" : url.pathExtension)"
            let backup = directory.appendingPathComponent(backupName)
            try? fileManager.removeItem(at: backup)
            let backedUp = (try? fileManager.copyItem(at: url, to: backup)) != nil

            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            let color = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
            originals.append(Original(
                displayID: id,
                path: url.path,
                backupName: backedUp ? backupName : nil,
                scaling: options[.imageScaling] as? Int,
                allowClipping: options[.allowClipping] as? Bool,
                fillColor: color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent].map(Double.init) }
            ))
        }
        guard !originals.isEmpty, let data = try? JSONEncoder().encode(originals) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func loadOriginals() -> [Original]? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode([Original].self, from: data)
    }

    private func resolvedURL(for original: Original) -> URL? {
        if fileManager.fileExists(atPath: original.path) {
            return URL(fileURLWithPath: original.path)
        }
        guard let backupName = original.backupName else { return nil }
        let backup = directory.appendingPathComponent(backupName)
        let pictures = fileManager.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let restored = pictures.appendingPathComponent("Desktop Picture (restored).\(backup.pathExtension)")
        try? fileManager.removeItem(at: restored)
        return (try? fileManager.copyItem(at: backup, to: restored)) != nil ? restored : nil
    }

    private func options(for original: Original) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = original.scaling { options[.imageScaling] = scaling }
        if let allowClipping = original.allowClipping { options[.allowClipping] = allowClipping }
        if let c = original.fillColor, c.count == 4 {
            options[.fillColor] = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
        }
        return options
    }

    private func removeFrames(except keep: URL) {
        let frames = (try? fileManager.contentsOfDirectory(at: framesDirectory, includingPropertiesForKeys: nil)) ?? []
        for frame in frames where frame.lastPathComponent != keep.lastPathComponent {
            try? fileManager.removeItem(at: frame)
        }
    }

    private nonisolated static func exportFrame(from video: URL, into directory: URL) async throws -> URL {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: .zero)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
