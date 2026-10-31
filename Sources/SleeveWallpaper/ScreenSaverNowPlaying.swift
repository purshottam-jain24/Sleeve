import AppKit
import UniformTypeIdentifiers

/// What the screensaver shows while music plays. The screensaver runs in a separate
/// macOS process, so this is shared as a small JSON file next to the cover image.
/// The screensaver decodes the same keys (see Screensaver/SleeveSaverView.swift).
public struct NowPlayingCard: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double?
    /// Position in seconds at `positionDate`; the screensaver interpolates while playing.
    public var position: Double?
    public var positionDate: Date
    public var isPlaying: Bool
    /// The app playing it ("Spotify", "Google Chrome").
    public var playerName: String?
    /// File name of the cover, in the same folder.
    var artworkFile: String?

    public init(title: String, artist: String, album: String, duration: Double?, position: Double?, positionDate: Date, isPlaying: Bool, playerName: String? = nil) {
        self.playerName = playerName
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.positionDate = positionDate
        self.isPlaying = isPlaying
    }

    /// Where playback is at `date`.
    func predictedPosition(at date: Date) -> Double? {
        guard let position else { return nil }
        return isPlaying ? position + date.timeIntervalSince(positionDate) : position
    }
}

/// Writes `NowPlaying/card.json` and the cover for the screensaver, skipping writes that
/// wouldn't change what it shows (the position only matters when it jumps).
final class ScreenSaverNowPlayingWriter {
    private let directory: URL
    private var cardURL: URL { directory.appendingPathComponent("card.json") }
    private var lastCard: NowPlayingCard?
    private var artworkKey: String?
    private var artworkFile: String?

    init(directory: URL) {
        self.directory = directory
    }

    func write(_ card: NowPlayingCard, artwork: NSImage?, artworkKey key: String?) {
        var card = card
        if let key, key != artworkKey, let artwork, let file = saveArtwork(artwork) {
            artworkKey = key
            artworkFile = file
        }
        card.artworkFile = artworkFile
        if let lastCard, Self.isEquivalent(lastCard, card) { return }
        guard let data = try? JSONEncoder().encode(card) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cardURL, options: .atomic)
        lastCard = card
    }

    /// Removes the card; the screensaver goes back to the wallpaper video.
    func clear() {
        lastCard = nil
        artworkKey = nil
        artworkFile = nil
        try? FileManager.default.removeItem(at: directory)
    }

    static func isEquivalent(_ a: NowPlayingCard, _ b: NowPlayingCard) -> Bool {
        guard a.title == b.title, a.artist == b.artist, a.album == b.album, a.duration == b.duration,
              a.isPlaying == b.isPlaying, a.playerName == b.playerName, a.artworkFile == b.artworkFile else { return false }
        let now = Date()
        switch (a.predictedPosition(at: now), b.predictedPosition(at: now)) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x - y) < 1.5
        default: return false
        }
    }

    private func saveArtwork(_ image: NSImage) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "cover-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        // Keep only the new cover (and the card).
        for old in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        where old.hasPrefix("cover-") && old != name {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
        }
        return name
    }
}
