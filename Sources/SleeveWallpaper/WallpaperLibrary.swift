import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

/// A video in the wallpaper library.
public struct WallpaperVideo: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    let fileName: String
    let addedAt: Date
    public var duration: Double
}

public enum WallpaperLibraryError: LocalizedError {
    case notPlayable(String)

    public var errorDescription: String? {
        switch self {
        case .notPlayable(let name): "“\(name)” isn’t a video macOS can play."
        }
    }
}

/// Imported videos with thumbnails and short hover previews, stored in
/// `~/Library/Application Support/Sleeve/Wallpaper/Library/`.
@MainActor
@Observable
public final class WallpaperLibrary {
    nonisolated public static let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sleeve/Wallpaper", isDirectory: true)
    /// Where the standalone LiveWallpaper app kept its library.
    nonisolated public static let legacyRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LiveWallpaper", isDirectory: true)

    public private(set) var videos: [WallpaperVideo] = []
    public private(set) var previewsReady: Set<UUID> = []
    public private(set) var importingCount = 0

    let root: URL
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("library.json") }
    @ObservationIgnored private var thumbnails: [UUID: NSImage] = [:]

    public init(root: URL = WallpaperLibrary.defaultRoot) {
        self.root = root
        directory = root.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        previewsReady = Set(videos.filter { FileManager.default.fileExists(atPath: previewURL(for: $0.id).path) }.map(\.id))
    }

    /// Generates hover previews that are missing (after an import from LiveWallpaper or
    /// an interrupted export). Runs at utility priority, one video at a time.
    public func preparePreviews() async {
        for video in videos where !previewsReady.contains(video.id) {
            await makePreview(for: video)
        }
    }

    public func previewURL(for video: WallpaperVideo) -> URL? {
        previewsReady.contains(video.id) ? previewURL(for: video.id) : nil
    }

    public func videoURL(for video: WallpaperVideo) -> URL {
        directory.appendingPathComponent(video.fileName)
    }

    public func thumbnail(for video: WallpaperVideo) -> NSImage? {
        if let cached = thumbnails[video.id] { return cached }
        let image = NSImage(contentsOf: thumbnailURL(for: video.id))
        thumbnails[video.id] = image
        return image
    }

    public func video(withID id: UUID?) -> WallpaperVideo? {
        videos.first { $0.id == id }
    }

    public func importVideo(from source: URL) async throws -> WallpaperVideo {
        importingCount += 1
        defer { importingCount -= 1 }
        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("\(id.uuidString).\(ext)")
        let thumbnail = thumbnailURL(for: id)

        let duration = try await Task.detached(priority: .userInitiated) {
            try await Self.prepare(source: source, destination: destination, thumbnail: thumbnail)
        }.value

        let video = WallpaperVideo(id: id, name: source.deletingPathExtension().lastPathComponent,
                                   fileName: destination.lastPathComponent, addedAt: .now, duration: duration)
        videos.insert(video, at: 0)
        save()
        Task { await makePreview(for: video) }
        return video
    }

    public func rename(_ video: WallpaperVideo, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = videos.firstIndex(of: video) else { return }
        videos[index].name = trimmed
        save()
    }

    public func delete(_ video: WallpaperVideo) {
        try? FileManager.default.removeItem(at: videoURL(for: video))
        try? FileManager.default.removeItem(at: thumbnailURL(for: video.id))
        try? FileManager.default.removeItem(at: previewURL(for: video.id))
        thumbnails[video.id] = nil
        previewsReady.remove(video.id)
        videos.removeAll { $0.id == video.id }
        save()
    }

    /// Copies the standalone LiveWallpaper app's library in once, when ours is empty.
    /// On APFS the copies are clones, so they take no extra disk space.
    /// - Returns: the number of videos brought over.
    @discardableResult
    public func importLegacyLibrary(from legacyRoot: URL = WallpaperLibrary.legacyRoot) -> Int {
        let legacy = legacyRoot.appendingPathComponent("Library", isDirectory: true)
        guard videos.isEmpty,
              let data = try? Data(contentsOf: legacy.appendingPathComponent("library.json")),
              let stored = try? JSONDecoder().decode([WallpaperVideo].self, from: data) else { return 0 }
        let fm = FileManager.default
        var imported: [WallpaperVideo] = []
        for video in stored {
            let source = legacy.appendingPathComponent(video.fileName)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent(video.fileName)
            guard (try? fm.copyItem(at: source, to: destination)) != nil || fm.fileExists(atPath: destination.path) else { continue }
            for name in ["\(video.id.uuidString).jpg", "\(video.id.uuidString)-preview.mp4"] {
                try? fm.copyItem(at: legacy.appendingPathComponent(name), to: directory.appendingPathComponent(name))
            }
            imported.append(video)
        }
        guard !imported.isEmpty else { return 0 }
        videos = imported
        previewsReady = Set(imported.filter { fm.fileExists(atPath: previewURL(for: $0.id).path) }.map(\.id))
        save()
        return imported.count
    }

    private func makePreview(for video: WallpaperVideo) async {
        let source = videoURL(for: video)
        let destination = previewURL(for: video.id)
        let duration = video.duration
        let succeeded = await Task.detached(priority: .utility) {
            await Self.exportPreview(from: source, to: destination, duration: duration)
        }.value
        if succeeded, videos.contains(where: { $0.id == video.id }) {
            previewsReady.insert(video.id)
        }
    }

    private nonisolated static func exportPreview(from source: URL, to destination: URL, duration: Double) async -> Bool {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent)")
        try? FileManager.default.removeItem(at: staging)
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPreset960x540) else { return false }
        exporter.outputURL = staging
        exporter.outputFileType = .mp4
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: min(10, max(duration, 1)), preferredTimescale: 600))
        await exporter.export()
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: staging)
            return false
        }
        try? FileManager.default.removeItem(at: destination)
        return (try? FileManager.default.moveItem(at: staging, to: destination)) != nil
    }

    private func previewURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString)-preview.mp4")
    }

    private func thumbnailURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([WallpaperVideo].self, from: data) else { return }
        videos = stored.filter { FileManager.default.fileExists(atPath: videoURL(for: $0).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(videos) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private nonisolated static func prepare(source: URL, destination: URL, thumbnail: URL) async throws -> Double {
        let asset = AVURLAsset(url: source)
        guard try await asset.load(.isPlayable) else {
            throw WallpaperLibraryError.notPlayable(source.lastPathComponent)
        }
        let duration = try await asset.load(.duration).seconds

        try FileManager.default.copyItem(at: source, to: destination)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        let time = CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)
        if let (image, _) = try? await generator.image(at: time),
           let output = CGImageDestinationCreateWithURL(thumbnail as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            CGImageDestinationFinalize(output)
        }
        return duration
    }
}
