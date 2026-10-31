import AppKit
import Foundation
import Observation

/// The app-wide view of "what is playing right now", including artwork and its palette.
@MainActor
@Observable
public final class NowPlayingService {
    public private(set) var snapshot: PlaybackSnapshot?
    public private(set) var artwork: NSImage?
    public private(set) var palette: ArtworkPalette = .fallback
    public private(set) var lastCommandError: MusicSourceError?

    public let sources: MusicSourceManager

    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var resyncTask: Task<Void, Never>?
    @ObservationIgnored private let extractor = ArtworkColorExtractor()
    @ObservationIgnored private var artworkCache: [String: (NSImage, ArtworkPalette)] = [:]
    @ObservationIgnored private var artworkCacheOrder: [String] = []

    public init(sources: MusicSourceManager) {
        self.sources = sources
        sources.onActiveChange = { [weak self] snapshot in self?.apply(snapshot) }
    }

    public var isPlaying: Bool { snapshot?.state == .playing }

    public func position(at date: Date = Date()) -> TimeInterval? {
        snapshot?.position(at: date)
    }

    public func perform(_ command: PlaybackCommand) {
        Task {
            do throws(MusicSourceError) {
                try await sources.perform(command)
                lastCommandError = nil
            } catch {
                lastCommandError = error
            }
        }
    }

    #if DEBUG
    /// Layout snapshots only: shows a fixed track without a real player.
    public func debugShow(_ snapshot: PlaybackSnapshot, artwork image: NSImage) {
        artworkTask?.cancel()
        self.snapshot = snapshot
        artworkKey = "debug:\(snapshot.track?.cacheKey ?? "")"
        artwork = image
        palette = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap { extractor.palette(from: $0) } ?? .fallback
    }
    #endif

    private func apply(_ next: PlaybackSnapshot?) {
        snapshot = next
        updateArtwork(for: next)
        updateResync()
    }

    // MARK: Artwork

    private func updateArtwork(for snapshot: PlaybackSnapshot?) {
        guard let track = snapshot?.track else {
            artworkTask?.cancel()
            artworkKey = nil
            artwork = nil
            palette = .fallback
            return
        }
        // Spotify only learns the artwork URL after the scripted refresh; including it in
        // the key retries exactly once when it arrives instead of polling for artwork.
        let key = "\(snapshot!.source.rawValue):\(track.cacheKey):\(track.artworkURL?.absoluteString ?? "")"
        guard key != artworkKey else { return }
        // Avoid flashing the placeholder between a Spotify notification and the scripted
        // refresh that supplies the artwork URL (unless scripting is unavailable).
        if snapshot!.source == .spotify, track.artworkURL == nil, !snapshot!.isEnriched,
           sources.provider(for: .spotify)?.status == .connected {
            return
        }
        artworkKey = key

        if let cached = artworkCache[key] {
            artworkTask?.cancel()
            artworkTask = nil
            artwork = cached.0
            palette = cached.1
            return
        }

        artworkTask?.cancel()
        let provider = sources.provider(for: snapshot!.source)
        let extractor = extractor
        artworkTask = Task { [weak self] in
            let data = await provider?.artworkData(for: track)
            guard !Task.isCancelled else { return }
            guard let data else {
                self?.finishArtwork(key: key, image: nil, palette: .fallback)
                return
            }
            let palette = await Task.detached(priority: .userInitiated) {
                extractor.palette(fromImageData: data)
            }.value
            guard !Task.isCancelled else { return }
            self?.finishArtwork(key: key, image: NSImage(data: data), palette: palette ?? .fallback)
        }
    }

    private func finishArtwork(key: String, image: NSImage?, palette: ArtworkPalette) {
        guard key == artworkKey else { return }
        artworkTask = nil
        artwork = image
        self.palette = palette
        guard let image else { return }
        artworkCache[key] = (image, palette)
        artworkCacheOrder.append(key)
        if artworkCacheOrder.count > 24 {
            artworkCache.removeValue(forKey: artworkCacheOrder.removeFirst())
        }
    }

    // MARK: Position resync

    /// While playing, re-query every 5 s to correct drift; idle sources are not polled.
    private func updateResync() {
        guard isPlaying else {
            resyncTask?.cancel()
            resyncTask = nil
            return
        }
        guard resyncTask == nil else { return }
        resyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, self.isPlaying else { break }
                await self.sources.activeProvider?.refresh()
            }
        }
    }
}
