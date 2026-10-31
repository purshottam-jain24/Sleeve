import Foundation

/// Local Spotify desktop integration (no account or network needed for now playing).
///
/// Push updates come from the `com.spotify.client.PlaybackStateChanged` distributed
/// notification; position, volume and artwork URL are read via Apple Events.
@MainActor
public final class SpotifyService: ScriptablePlayerProvider {
    public init() {
        super.init(source: .spotify, notificationName: "com.spotify.client.PlaybackStateChanged")
    }

    private static let stateScript = """
    tell application "Spotify"
        set s to player state as string
        if s is "stopped" then return {s}
        set t to current track
        return {s, player position, sound volume, name of t, artist of t, album of t, duration of t, id of t, artwork url of t}
    end tell
    """

    override func snapshot(fromNotification info: [AnyHashable: Any]) -> PlaybackSnapshot? {
        let state = PlaybackState(playerState: info["Player State"] as? String)
        guard state != .stopped, let title = info["Name"] as? String else {
            return PlaybackSnapshot(source: .spotify, state: .stopped, track: nil)
        }
        let durationMS = (info["Duration"] as? NSNumber)?.doubleValue
        let track = Track(
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: durationMS.map { $0 / 1000 },
            identifier: info["Track ID"] as? String
        )
        return PlaybackSnapshot(
            source: .spotify,
            state: state,
            track: track,
            position: (info["Playback Position"] as? NSNumber)?.doubleValue
        )
    }

    override func fetchStateViaScript() async throws(MusicSourceError) -> PlaybackSnapshot {
        try await runner.run(Self.stateScript) { d in
            let state = PlaybackState(playerState: d.item(1)?.stringValue)
            guard state != .stopped, let title = d.item(4)?.stringValue else {
                return PlaybackSnapshot(source: .spotify, state: .stopped, track: nil)
            }
            let durationMS = d.item(7)?.doubleValue ?? 0
            let track = Track(
                title: title,
                artist: d.item(5)?.stringValue ?? "",
                album: d.item(6)?.stringValue ?? "",
                duration: durationMS > 0 ? durationMS / 1000 : nil,
                identifier: d.item(8)?.nonEmptyString,
                artworkURL: d.item(9)?.nonEmptyString.flatMap(URL.init(string:))
            )
            return PlaybackSnapshot(
                source: .spotify,
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
        return "tell application \"Spotify\" to \(body)"
    }

    override public func artworkData(for track: Track) async -> Data? {
        // The notification never carries the artwork URL; ask the player if we lack it.
        var url = track.artworkURL
        if url == nil, snapshot?.track?.cacheKey == track.cacheKey {
            url = snapshot?.track?.artworkURL
        }
        guard let url, url.scheme == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            Log.artwork.error("Spotify artwork download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
