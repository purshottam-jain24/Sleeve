import Foundation

/// Identifies a music source. Raw values are persisted in settings.
public enum MusicSourceID: String, Codable, Sendable, CaseIterable, Identifiable {
    case spotify
    case appleMusic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Music"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }
}

public enum PlaybackState: String, Sendable, Equatable {
    case playing
    case paused
    case stopped
}

public struct Track: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds. `nil` for streams/radio where the source does not report a duration.
    public var duration: TimeInterval?
    /// Source-specific stable identifier (Spotify URI, Music persistent ID).
    public var identifier: String?
    public var artworkURL: URL?

    public init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval? = nil,
        identifier: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.identifier = identifier
        self.artworkURL = artworkURL
    }

    /// Key used for artwork/lyrics caching when no identifier is available.
    public var cacheKey: String {
        identifier ?? "\(artist)\u{1F}\(album)\u{1F}\(title)"
    }
}

public struct PlaybackSnapshot: Sendable, Equatable {
    public var source: MusicSourceID
    public var state: PlaybackState
    public var track: Track?
    /// Position in seconds at `positionTimestamp`.
    public var position: TimeInterval?
    public var positionTimestamp: Date
    /// 0...1, `nil` when unknown.
    public var volume: Double?
    /// `true` when produced by a full scripted query rather than a lightweight notification.
    public var isEnriched: Bool

    public init(
        source: MusicSourceID,
        state: PlaybackState,
        track: Track?,
        position: TimeInterval? = nil,
        positionTimestamp: Date = Date(),
        volume: Double? = nil,
        isEnriched: Bool = false
    ) {
        self.source = source
        self.state = state
        self.track = track
        self.position = position
        self.positionTimestamp = positionTimestamp
        self.volume = volume
        self.isEnriched = isEnriched
    }

    /// Interpolated playback position at `date`, clamped to the track duration.
    public func position(at date: Date) -> TimeInterval? {
        guard let position else { return nil }
        var value = position
        if state == .playing {
            value += max(0, date.timeIntervalSince(positionTimestamp))
        }
        if let duration = track?.duration, duration > 0 {
            value = min(value, duration)
        }
        return max(0, value)
    }
}

public enum PlaybackCommand: Sendable, Equatable {
    case playPause
    case next
    case previous
    case seek(TimeInterval)
    /// 0...1
    case setVolume(Double)
}
