import Foundation
import Testing
@testable import SleeveCore

struct LyricsTests {
    @Test func parsesTimestampsMetadataAndRepeats() {
        let lrc = """
        [ar:Someone]
        [ti:Song]
        [00:12.50]First line
        [00:05.00][01:00.25]Chorus
        [00:20]
        [01:02:50]Colon fraction
        not a lyric
        """
        let lines = LRCParser.parse(lrc)
        #expect(lines.map(\.text) == ["Chorus", "First line", "", "Chorus", "Colon fraction"])
        #expect(lines.map(\.time) == [5, 12.5, 20, 60.25, 62.5])
        #expect(lines.map(\.id) == [0, 1, 2, 3, 4])
        #expect(lines[2].isGap)
    }

    @Test func appliesOffsetTag() {
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00]Hello")
        #expect(lines.first?.time == 9.5)
    }

    @Test func parsesEnhancedWordTimings() {
        let lines = LRCParser.parse("[00:10.00]<00:10.00>Hello <00:10.80>bright <00:11.40>world")
        #expect(lines.first?.text == "Hello bright world")
        #expect(lines.first?.words.map(\.time) == [10, 10.8, 11.4])
    }

    @Test func findsActiveLineAndProgress() {
        let doc = LyricsDocument(synced: LRCParser.parse("[00:10.00]A\n[00:20.00]B\n[00:30.00]C"), plain: [], sourceName: "test")
        #expect(doc.lineIndex(at: 5) == nil)
        #expect(doc.lineIndex(at: 10) == 0)
        #expect(doc.lineIndex(at: 25) == 1)
        #expect(doc.lineIndex(at: 999) == 2)
        #expect(doc.progress(ofLine: 1, at: 25, trackDuration: nil) == 0.5)
    }

    @Test func cleansTitlesAndArtists() {
        #expect(LyricsMatching.cleanTitle("Here Comes the Sun - Remastered 2009") == "Here Comes the Sun")
        #expect(LyricsMatching.cleanTitle("Song (feat. Someone)") == "Song")
        #expect(LyricsMatching.cleanTitle("Song (Interlude)") == "Song (Interlude)")
        #expect(LyricsMatching.primaryArtist("Daft Punk, Pharrell Williams") == "Daft Punk")
    }

    @Test func matchingPrefersDurationAndSyncedAndRejectsFarDurations() {
        let candidates: [(String, LyricsMatching.Candidate)] = [
            ("wrong-length", .init(title: "Get Lucky", artist: "Daft Punk", duration: 369, hasSynced: true)),
            ("plain", .init(title: "Get Lucky", artist: "Daft Punk", duration: 248, hasSynced: false)),
            ("best", .init(title: "Get Lucky (feat. Pharrell)", artist: "Daft Punk", duration: 249, hasSynced: true)),
            ("other-song", .init(title: "Lose Yourself to Dance", artist: "Daft Punk", duration: 248, hasSynced: true)),
        ]
        #expect(LyricsMatching.best(candidates, title: "Get Lucky", artist: "Daft Punk", duration: 248) == "best")
        #expect(LyricsMatching.best([candidates[0]], title: "Get Lucky", artist: "Daft Punk", duration: 248) == nil)
    }

    @Test func titleOnlyMatchingNeedsTheArtistOrTheLength() {
        let candidates: [(String, LyricsMatching.Candidate)] = [
            ("synced", .init(title: "ANTIDOTE", artist: "Karan Aujla", duration: 180, hasSynced: true)),
            ("plain", .init(title: "Antidote", artist: "Karan Aujla", duration: nil, hasSynced: false)),
            ("other-title", .init(title: "Antidote Remix Pack", artist: "Someone", duration: 200, hasSynced: true)),
        ]
        // The channel name overlaps the artist.
        #expect(LyricsMatching.unambiguous(candidates, title: "ANTIDOTE", artistHint: "Karan Aujla - Topic", duration: nil) == "synced")
        // A label as "artist" and no length: nothing to verify against, so no guess.
        #expect(LyricsMatching.unambiguous(candidates, title: "ANTIDOTE", artistHint: "Brown Town Music", duration: nil) == nil)
        // The only same-named song is by someone else: never shown.
        let wrongOnly: [(String, LyricsMatching.Candidate)] = [("travis", .init(title: "Antidote", artist: "Travis Scott", duration: 262, hasSynced: true))]
        #expect(LyricsMatching.unambiguous(wrongOnly, title: "ANTIDOTE", artistHint: "Karan Aujla", duration: nil) == nil)
        // A matching length is enough when the artist is unknown.
        #expect(LyricsMatching.unambiguous(candidates + wrongOnly, title: "ANTIDOTE", artistHint: "", duration: 181) == "synced")
    }

    @Test func bestRejectsSameTitleByAnotherArtist() {
        let candidates: [(String, LyricsMatching.Candidate)] = [
            ("other", .init(title: "Alfaaz", artist: "Someone Else", duration: 200, hasSynced: true)),
        ]
        #expect(LyricsMatching.best(candidates, title: "Alfaaz", artist: "Hamza Malik", duration: nil) == nil)
        #expect(LyricsMatching.best(candidates, title: "Alfaaz", artist: "Hamza Malik", duration: 260) == nil)
        // Collaborations match on a shared name.
        let collab: [(String, LyricsMatching.Candidate)] = [("ok", .init(title: "Alfaaz", artist: "Zain Zohaib & Hamza Malik", duration: nil, hasSynced: true))]
        #expect(LyricsMatching.best(collab, title: "Alfaaz", artist: "Hamza Malik", duration: nil) == "ok")
    }

    @Test func providerResultNeverInventsLyrics() {
        let empty = LRCLibProvider.Record(id: 1, trackName: "x", artistName: "y", albumName: nil, duration: 1, instrumental: false, plainLyrics: "", syncedLyrics: nil)
        #expect(LRCLibProvider.result(from: empty) == nil)
        let instrumental = LRCLibProvider.Record(id: 2, trackName: nil, artistName: nil, albumName: nil, duration: nil, instrumental: true, plainLyrics: nil, syncedLyrics: nil)
        #expect(LRCLibProvider.result(from: instrumental) == .instrumental)
    }

    @Test func cacheRoundTripsAndExpiresNotFound() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = LyricsCache(directory: dir)
        let track = Track(title: "T", artist: "A", album: "B", duration: 200)
        let doc = LyricsDocument(synced: LRCParser.parse("[00:01.00]Hi"), plain: ["Hi"], sourceName: "LRCLIB")
        cache.store(.found(doc), for: track)
        #expect(cache.result(for: track) == .found(doc))
        try? FileManager.default.removeItem(at: dir)
    }
}
