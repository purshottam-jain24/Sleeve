import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SleeveWallpaper

@MainActor
struct WallpaperLibraryTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sleeve-wallpaper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func importsTheStandaloneAppsLibraryOnce() throws {
        let legacy = try temporaryDirectory()
        let legacyLibrary = legacy.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: legacyLibrary, withIntermediateDirectories: true)
        let id = UUID()
        try Data("video".utf8).write(to: legacyLibrary.appendingPathComponent("\(id.uuidString).mov"))
        try Data("jpg".utf8).write(to: legacyLibrary.appendingPathComponent("\(id.uuidString).jpg"))
        let missing = UUID()
        let index = """
        [{"id":"\(id.uuidString)","name":"Rain","fileName":"\(id.uuidString).mov","addedAt":0,"duration":12},
         {"id":"\(missing.uuidString)","name":"Gone","fileName":"\(missing.uuidString).mov","addedAt":0,"duration":5}]
        """
        try Data(index.utf8).write(to: legacyLibrary.appendingPathComponent("library.json"))

        let root = try temporaryDirectory()
        let library = WallpaperLibrary(root: root)
        #expect(library.importLegacyLibrary(from: legacy) == 1)
        #expect(library.videos.map(\.name) == ["Rain"])
        #expect(FileManager.default.fileExists(atPath: library.videoURL(for: library.videos[0]).path))
        // The originals stay where they were.
        #expect(FileManager.default.fileExists(atPath: legacyLibrary.appendingPathComponent("\(id.uuidString).mov").path))
        // Not repeated once the library has videos, and it persists.
        #expect(library.importLegacyLibrary(from: legacy) == 0)
        #expect(WallpaperLibrary(root: root).videos.count == 1)
    }

    @Test func rendersAnArtworkPictureAtDisplaySize() throws {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.4, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let url = try ArtworkWallpaper.render(ctx.makeImage()!, pixelSize: CGSize(width: 320, height: 200), into: try temporaryDirectory())
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 320 && image.height == 200)
    }
}
