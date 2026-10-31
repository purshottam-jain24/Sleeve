import Foundation
import Testing
@testable import SleeveCore

struct PlaybackTests {
    let track = Track(title: "T", artist: "A", album: "B", duration: 100)

    @Test func interpolatesWhilePlayingAndClampsToDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let snap = PlaybackSnapshot(source: .spotify, state: .playing, track: track, position: 10, positionTimestamp: start)
        #expect(snap.position(at: start.addingTimeInterval(5)) == 15)
        #expect(snap.position(at: start.addingTimeInterval(500)) == 100)
        var paused = snap
        paused.state = .paused
        #expect(paused.position(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func parsesPlayerStates() {
        #expect(PlaybackState(playerState: "Playing") == .playing)
        #expect(PlaybackState(playerState: "paused") == .paused)
        #expect(PlaybackState(playerState: "fast forwarding") == .playing)
        #expect(PlaybackState(playerState: nil) == .stopped)
    }

    @Test func playingSourceWinsThenPriorityThenStickiness() {
        let settings = SourceSettings() // spotify before appleMusic
        let spotifyPaused = PlaybackSnapshot(source: .spotify, state: .paused, track: track)
        let musicPlaying = PlaybackSnapshot(source: .appleMusic, state: .playing, track: track)
        let musicPaused = PlaybackSnapshot(source: .appleMusic, state: .paused, track: track)
        let spotifyPlaying = PlaybackSnapshot(source: .spotify, state: .playing, track: track)

        #expect(MusicSourceManager.selectActive(candidates: [spotifyPaused, musicPlaying], previous: nil, settings: settings)?.source == .appleMusic)
        #expect(MusicSourceManager.selectActive(candidates: [musicPlaying, spotifyPlaying], previous: nil, settings: settings)?.source == .spotify)
        #expect(MusicSourceManager.selectActive(candidates: [spotifyPaused, musicPaused], previous: musicPaused, settings: settings)?.source == .appleMusic)
        #expect(MusicSourceManager.selectActive(candidates: [spotifyPaused, musicPaused], previous: nil, settings: settings)?.source == .spotify)
        #expect(MusicSourceManager.selectActive(candidates: [], previous: musicPaused, settings: settings) == nil)
    }

    @MainActor @Test func parsesSpotifyNotificationPayload() {
        let service = SpotifyService()
        let snap = service.snapshot(fromNotification: [
            "Player State": "Playing", "Name": "Song", "Artist": "Artist", "Album": "Album",
            "Track ID": "spotify:track:abc", "Duration": NSNumber(value: 215_000), "Playback Position": NSNumber(value: 12.5),
        ])
        #expect(snap?.state == .playing)
        #expect(snap?.track?.duration == 215)
        #expect(snap?.track?.identifier == "spotify:track:abc")
        #expect(snap?.position == 12.5)
        #expect(service.snapshot(fromNotification: ["Player State": "Stopped"])?.track == nil)
    }

    @MainActor @Test func parsesMusicNotificationPayload() {
        let service = AppleMusicService()
        let snap = service.snapshot(fromNotification: [
            "Player State": "Paused", "Name": "Song", "Artist": "Artist", "Album": "Album",
            "Total Time": NSNumber(value: 180_000), "PersistentID": NSNumber(value: Int64(-2)),
        ])
        #expect(snap?.state == .paused)
        #expect(snap?.track?.duration == 180)
        // Must match the hex form AppleScript returns so artwork/caches line up.
        #expect(snap?.track?.identifier == "FFFFFFFFFFFFFFFE")
    }
}
