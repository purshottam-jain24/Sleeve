import Foundation
import Testing
@testable import SleeveCore

struct WebMediaTests {
    @Test func recognisesMediaSites() {
        func site(_ s: String) -> WebMediaSite? { WebMediaSite.site(for: URL(string: s)!) }
        #expect(site("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10") == .youtube)
        #expect(site("https://youtu.be/dQw4w9WgXcQ") == .youtube)
        #expect(site("https://www.youtube.com/shorts/dQw4w9WgXcQ") == .youtube)
        #expect(site("https://music.youtube.com/watch?v=dQw4w9WgXcQ") == .youtubeMusic)
        #expect(site("https://www.youtube.com/") == nil)            // home page isn't media
        #expect(site("https://www.youtube.com/@channel") == nil)
        #expect(site("https://soundcloud.com/artist/track") == .soundcloud)
        #expect(site("https://open.spotify.com/track/123") == .spotifyWeb)
        #expect(site("https://notyoutube.com/watch?v=dQw4w9WgXcQ") == nil)
        #expect(site("https://example.com") == nil)
    }

    @Test func extractsYouTubeVideoIDs() {
        func id(_ s: String) -> String? { WebMediaSite.youtubeVideoID(from: URL(string: s)!) }
        #expect(id("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(id("https://youtu.be/dQw4w9WgXcQ?si=abc") == "dQw4w9WgXcQ")
        #expect(id("https://www.youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(id("https://www.youtube.com/live/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(id("https://www.youtube.com/watch?v=short") == nil)
        #expect(WebMediaSite.youtubeThumbnailURLs(videoID: "dQw4w9WgXcQ").first?.absoluteString
                == "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg")
    }

    @Test func cleansTabTitles() {
        let a = WebMediaSite.parseTitle("(3) Arpit Bala - Rakhlo Tum Chupaake - YouTube", site: .youtube)
        #expect(a.title == "Rakhlo Tum Chupaake" && a.artist == "Arpit Bala")
        let b = WebMediaSite.parseTitle("Lo-fi beats to relax - YouTube", site: .youtube)
        #expect(b.title == "Lo-fi beats to relax" && b.artist == "")
        let c = WebMediaSite.parseTitle("Some Song - YouTube Music", site: .youtubeMusic)
        #expect(c.title == "Some Song")
    }

    @Test func pageScriptsEmbedSafelyInAppleScript() {
        for js in [WebMediaScripts.readMedia, WebMediaScripts.playPause, WebMediaScripts.next, WebMediaScripts.previous] {
            #expect(!js.contains("\""))       // single quotes only
            #expect(!js.contains("\n"))       // one line
        }
        #expect(WebMediaScripts.appleScriptLiteral("a\"b\\c") == "a\\\"b\\\\c")
    }

    @Test func decodesPageMediaInfo() throws {
        let json = #"{"title":"Song","artist":"Artist","album":"","artwork":"https://x/y.jpg","paused":false,"time":12.5,"duration":200,"volume":1,"hasMedia":true}"#
        let info = try JSONDecoder().decode(PageMediaInfo.self, from: Data(json.utf8))
        #expect(info.paused == false && info.time == 12.5 && info.duration == 200)
    }

    @Test func browserAudioMatchesHelperProcesses() {
        let chrome = Browser.all.first { $0.name == "Google Chrome" }!
        #expect(chrome.isPlayingAudio(activeOutputs: ["com.google.Chrome.helper"]))
        #expect(!chrome.isPlayingAudio(activeOutputs: ["com.spotify.client"]))
    }

    @Test func newSourcesAreEnabledForExistingUsers() throws {
        let json = #"{"priority": ["spotify", "appleMusic"], "enabled": ["spotify", "appleMusic"]}"#
        let decoded = try JSONDecoder().decode(SourceSettings.self, from: Data(json.utf8))
        #expect(decoded.priority == [.spotify, .appleMusic, .web])
        #expect(decoded.enabled.contains(.web))
        // A source the user switched off stays off.
        let off = #"{"priority": ["spotify", "appleMusic", "web"], "enabled": ["spotify"]}"#
        #expect(!(try JSONDecoder().decode(SourceSettings.self, from: Data(off.utf8))).enabled.contains(.web))
    }

    @Test func channelNamesBecomeArtists() {
        #expect(WebMediaSite.artist(fromChannel: "Karan Aujla - Topic") == "Karan Aujla")
        #expect(WebMediaSite.artist(fromChannel: "TaylorSwiftVEVO") == "TaylorSwift")
        #expect(WebMediaSite.artist(fromChannel: "VEVO") == "VEVO")
        #expect(WebMediaSite.artist(fromChannel: "T-Series") == "T-Series")
        #expect(WebMediaSite.youtubeOEmbedURL(videoID: "dQw4w9WgXcQ")?.host == "www.youtube.com")
    }

    @Test func parsesSongAndSingerFromVideoTitles() {
        let a = WebMediaSite.parseTitle("The Beast (Official Audio) Cheema Y | Gur Sidhu | Punjabi Song 2024", site: .youtube)
        #expect(a.title == "The Beast" && a.artist == "Cheema Y")
        let b = WebMediaSite.parseTitle("Karan Aujla - ANTIDOTE (Official Video)", site: .youtube)
        #expect(b.title == "ANTIDOTE" && b.artist == "Karan Aujla")
        let c = WebMediaSite.parseTitle("Blinding Lights [4K]", site: .youtube)
        #expect(c.title == "Blinding Lights" && c.artist == "")
        // Brackets that are part of the song name stay.
        let d = WebMediaSite.parseTitle("Wake Me Up (Avicii Tribute)", site: .youtube)
        #expect(d.title == "Wake Me Up (Avicii Tribute)")
        // "Song - Official Video Song | Singer | Composer @handle": the dash part is a tag.
        let e = WebMediaSite.parseTitle("Kol Mere - Official Video Song | Ishan Krishan | Tushar Kaushik \u{202A}@rahi2607\u{202C} - YouTube", site: .youtube)
        #expect(e.title == "Kol Mere" && e.artist == "Ishan Krishan")
        let f = WebMediaSite.parseTitle("Tum Se Hi | Mohit Chauhan | Jab We Met", site: .youtube)
        #expect(f.title == "Tum Se Hi" && f.artist == "Mohit Chauhan")
        let g = WebMediaSite.parseTitle("Official Video - Kol Mere", site: .youtube)
        #expect(g.title == "Kol Mere")
        let h = WebMediaSite.parseTitle("O Sanam - Akhil Sachdeva ft Sara Gurpal || FanTiger Music NFT's - YouTube", site: .youtube)
        #expect(h.title == "O Sanam" && h.artist == "Akhil Sachdeva ft Sara Gurpal")
    }
}
