import Foundation

/// Music.app integration. MusicKit's `SystemMusicPlayer` is unavailable on macOS,
/// so state comes from the `com.apple.Music.playerInfo` notification plus Apple Events.
@MainActor
public final class AppleMusicService: ScriptablePlayerProvider {
    public init() {
        super.init(source: .appleMusic, notificationName: "com.apple.Music.playerInfo")
    }

    // Radio/stream items may have no `current track`; fall back to the stream title.
    private static let stateScript = """
    tell application "Music"
        set s to player state as string
        if s is "stopped" then return {s}
        set v to sound volume
        set p to 0
        try
            set p to player position
        end try
        try
            set t to current track
            return {s, p, v, name of t, artist of t, album of t, duration of t, persistent ID of t}
        on error
            set st to ""
            try
                set st to current stream title
            end try
            return {s, p, v, st, "", "", 0, ""}
        end try
    end tell
    """

    private static let artworkScript = """
    tell application "Music"
        try
            return raw data of artwork 1 of current track
        on error
            return ""
        end try
    end tell
    """

    override func snapshot(fromNotification info: [AnyHashable: Any]) -> PlaybackSnapshot? {
        let state = PlaybackState(playerState: info["Player State"] as? String)
        guard state != .stopped, let title = info["Name"] as? String else {
            return PlaybackSnapshot(source: .appleMusic, state: .stopped, track: nil)
        }
        let totalMS = (info["Total Time"] as? NSNumber)?.doubleValue
        let persistentID = (info["PersistentID"] as? NSNumber).map { String(format: "%016llX", $0.int64Value) }
        let track = Track(
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: totalMS.flatMap { $0 > 0 ? $0 / 1000 : nil },
            identifier: persistentID
        )
        return PlaybackSnapshot(source: .appleMusic, state: state, track: track)
    }

    override func fetchStateViaScript() async throws(MusicSourceError) -> PlaybackSnapshot {
        try await runner.run(Self.stateScript) { d in
            let state = PlaybackState(playerState: d.item(1)?.stringValue)
            guard state != .stopped, let title = d.item(4)?.nonEmptyString else {
                return PlaybackSnapshot(source: .appleMusic, state: state == .stopped ? .stopped : state, track: nil)
            }
            let duration = d.item(7)?.doubleValue ?? 0
            let track = Track(
                title: title,
                artist: d.item(5)?.stringValue ?? "",
                album: d.item(6)?.stringValue ?? "",
                duration: duration > 0 ? duration : nil,
                identifier: d.item(8)?.nonEmptyString
            )
            return PlaybackSnapshot(
                source: .appleMusic,
                state: state,
                track: track,
                position: d.item(2)?.doubleValue,
                volume: d.item(3).map { Double($0.int32Value) / 100 },
                isEnriched: true
            )
        }
    }

    override func commandScript(_ command: PlaybackCommand) -> String {
        let body = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        case .seek(let seconds): "set player position to \(formatNumber(max(0, seconds)))"
        case .setVolume(let v): "set sound volume to \(Int((min(max(v, 0), 1) * 100).rounded()))"
        }
        return "tell application \"Music\" to \(body)"
    }

    override public func artworkData(for track: Track) async -> Data? {
        guard isRunning, snapshot?.track?.cacheKey == track.cacheKey else { return nil }
        let data = try? await runner.run(Self.artworkScript) { d -> Data? in
            // A text descriptor means "no artwork"; image descriptors carry raw bytes.
            d.descriptorType == typeUnicodeText ? nil : d.data
        }
        guard let data, data.count > 64 else { return nil }
        return data
    }
}
