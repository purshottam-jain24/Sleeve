import Foundation

/// Browsers whose tabs can be read with Apple Events. Firefox has no tab scripting on
/// macOS and can't be supported.
public struct Browser: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable { case safari, chromium }

    public let name: String
    public let bundleID: String
    let kind: Kind
    /// Bundle-ID prefixes of the processes that actually play the browser's audio
    /// (Chrome uses helper processes; Safari plays through WebKit's GPU process).
    let audioProcessPrefixes: [String]

    public var id: String { bundleID }

    public static let all: [Browser] = [
        Browser(name: "Safari", bundleID: "com.apple.Safari", kind: .safari, audioProcessPrefixes: ["com.apple.Safari", "com.apple.WebKit"]),
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome", kind: .chromium, audioProcessPrefixes: ["com.google.Chrome"]),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser", kind: .chromium, audioProcessPrefixes: ["company.thebrowser"]),
        Browser(name: "Brave", bundleID: "com.brave.Browser", kind: .chromium, audioProcessPrefixes: ["com.brave.Browser"]),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", kind: .chromium, audioProcessPrefixes: ["com.microsoft.edgemac"]),
        Browser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", kind: .chromium, audioProcessPrefixes: ["com.vivaldi.Vivaldi"]),
    ]

    func isPlayingAudio(activeOutputs: Set<String>) -> Bool {
        activeOutputs.contains { id in audioProcessPrefixes.contains { id.hasPrefix($0) } }
    }

    /// Where to enable script access to page media info.
    public var javaScriptSettingHint: String {
        switch kind {
        case .safari: "In Safari, turn on Settings › Advanced › Show features for web developers, then Develop › Allow JavaScript from Apple Events."
        case .chromium: "In \(name), choose View › Developer › Allow JavaScript from Apple Events."
        }
    }
}

/// Known media sites, and how to identify what's playing from a tab's URL and title.
public enum WebMediaSite: String, Sendable, CaseIterable {
    case youtube, youtubeMusic, soundcloud, spotifyWeb, appleMusicWeb, bandcamp, deezer, tidal, vimeo, twitch

    public static func site(for url: URL) -> WebMediaSite? {
        guard let host = url.host?.lowercased() else { return nil }
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if host == "music.youtube.com" { return .youtubeMusic }
        if matches("youtube.com") || matches("youtu.be") || matches("youtube-nocookie.com") {
            return youtubeVideoID(from: url) != nil ? .youtube : nil
        }
        if matches("soundcloud.com") { return .soundcloud }
        if host == "open.spotify.com" { return .spotifyWeb }
        if host == "music.apple.com" { return .appleMusicWeb }
        if matches("bandcamp.com") { return .bandcamp }
        if matches("deezer.com") { return .deezer }
        if matches("tidal.com") { return .tidal }
        if matches("vimeo.com") { return .vimeo }
        if matches("twitch.tv") { return .twitch }
        return nil
    }

    /// Extracts the video ID from watch, short-link, Shorts, embed and live URLs.
    public static func youtubeVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host.hasSuffix("youtu.be") {
            candidate = parts.first
        } else if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            candidate = v
        } else if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
            candidate = parts[1]
        }
        guard let id = candidate, id.count == 11,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    /// Thumbnails in preference order. `maxresdefault`/`hq720` are 16:9 without bars;
    /// `hqdefault` always exists but is letterboxed.
    public static func youtubeThumbnailURLs(videoID: String) -> [URL] {
        ["maxresdefault.jpg", "hq720.jpg", "hqdefault.jpg"].compactMap { URL(string: "https://i.ytimg.com/vi/\(videoID)/\($0)") }
    }

    /// YouTube's public oEmbed endpoint (no key, no page scripting): video title and channel.
    public static func youtubeOEmbedURL(videoID: String) -> URL? {
        URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(videoID)")
    }

    /// Turns a YouTube channel name into an artist: "Karan Aujla - Topic" and
    /// "KaranAujlaVEVO" style channels name the artist; others are kept as they are.
    public static func artist(fromChannel channel: String) -> String {
        var name = channel.trimmingCharacters(in: .whitespaces)
        if name.hasSuffix(" - Topic") { name = String(name.dropLast(" - Topic".count)) }
        if name.count > 4, name.hasSuffix("VEVO") { name = String(name.dropLast(4)) }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Cleans a tab title: drops notification counts and the site suffix, and splits
    /// "Artist - Title" when present.
    public static func parseTitle(_ raw: String, site: WebMediaSite) -> (title: String, artist: String) {
        var title = raw.trimmingCharacters(in: .whitespaces)
        if title.hasPrefix("("), let close = title.firstIndex(of: ")"),
           title[title.index(after: title.startIndex)..<close].allSatisfy(\.isNumber) {
            title = String(title[title.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        for suffix in [" - YouTube Music", " - YouTube", " | SoundCloud", " | Spotify", " - Spotify", " on Apple Music", " | Bandcamp", " on Vimeo", " - Twitch"] {
            if title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)) }
        }
        guard site == .youtube else { return (title, "") }

        // Video titles: "Artist - Song (Official Video)", "Song (Official Audio) Artist | Label | …",
        // "Song - Official Video Song | Singer | Composer". After the first " | " come credits
        // and promotion; the first short name there is usually the singer.
        title = String(title.unicodeScalars.filter { !Self.directionMarks.contains($0) })
        let segments = title.replacingOccurrences(of: #"\s+\|+\s+"#, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}").map { $0.trimmingCharacters(in: .whitespaces) }
        title = segments[0]
        let creditedArtist = segments.dropFirst().first(where: isPlausibleName) ?? ""
        var artistHint = ""
        if let (song, trailing) = removingVideoTags(from: title) {
            title = song
            // Text after "(Official Audio)" is usually the singer; only trust short names.
            if trailing.split(separator: " ").count <= 4 { artistHint = trailing }
        }
        title = title.trimmingCharacters(in: .whitespaces)
        if let dash = title.range(of: " - ") {
            let left = String(title[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(title[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
            // "Song - Official Video Song": the part after the dash is a tag, not a song.
            if isBareTag(right) { return (left, artistHint.isEmpty ? creditedArtist : artistHint) }
            if isBareTag(left) { return (right, artistHint.isEmpty ? creditedArtist : artistHint) }
            // Usually "Artist - Song", but "Song - Singer ft Other" names the artists second.
            if !left.isEmpty, !right.isEmpty {
                return namesSeveralArtists(right) && !namesSeveralArtists(left) ? (left, right) : (right, left)
            }
        }
        return (title, artistHint.isEmpty ? creditedArtist : artistHint)
    }

    /// Invisible bidi marks YouTube puts around @handles.
    private static let directionMarks = Set("\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}".unicodeScalars)
    private static let tagPhrases = ["official", "audio", "video", "lyric", "visuali", "full song", "music video"]

    /// "Official Video Song", "Lyrical Video", "Full Audio": only tag words, no song name.
    static func isBareTag(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
        guard !lower.isEmpty, tagPhrases.contains(where: lower.contains) else { return false }
        let filler: Set<String> = ["official", "video", "song", "audio", "lyric", "lyrics", "lyrical", "full", "music", "new",
                                   "latest", "hd", "4k", "visualizer", "visualiser", "the", "with", "and", "&", "version", "track"]
        return lower.split(separator: " ").allSatisfy { filler.contains(String($0)) }
    }

    /// "A ft B", "A feat. B", "A x B", "A & B": a credit line, not a song name.
    static func namesSeveralArtists(_ text: String) -> Bool {
        text.range(of: #"(?i)\s(ft\.?|feat\.?|featuring|x|&)\s"#, options: .regularExpression) != nil
    }

    /// A credit that's probably a person: one to four words, no tags, handles or hashtags.
    static func isPlausibleName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (1...4).contains(words.count), !text.contains("@"), !text.contains("#"), !text.contains(":") else { return false }
        let lower = text.lowercased()
        return !tagPhrases.contains(where: lower.contains) && !text.contains(where: \.isNumber)
    }

    /// Removes "(Official Video)", "[Lyrics]", "(4K)" and similar. Returns the text before
    /// the first such tag and any text after the tags, or nil when there were none.
    static func removingVideoTags(from title: String) -> (String, String)? {
        let phrases = tagPhrases
        let tokens: Set<String> = ["hd", "hq", "4k", "mv", "m/v"]
        var result = title
        var firstTag: String.Index?
        var searchFrom = result.startIndex
        while let open = result[searchFrom...].firstIndex(where: { $0 == "(" || $0 == "[" }) {
            let closeChar: Character = result[open] == "(" ? ")" : "]"
            guard let close = result[open...].firstIndex(of: closeChar) else { break }
            let inner = result[result.index(after: open)..<close].lowercased()
            if phrases.contains(where: inner.contains) || tokens.contains(inner.trimmingCharacters(in: .whitespaces)) {
                let offset = result.distance(from: result.startIndex, to: open)
                result.removeSubrange(open...close)
                let at = result.index(result.startIndex, offsetBy: offset)
                if firstTag == nil { firstTag = at }
                searchFrom = at
            } else {
                searchFrom = result.index(after: close)
            }
        }
        guard let firstTag else { return nil }
        let head = String(result[..<firstTag]).trimmingCharacters(in: .whitespaces)
        let tail = String(result[firstTag...]).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !head.isEmpty else { return (tail, "") }
        return (head, tail)
    }
}

/// Page media state reported by the in-page script.
struct PageMediaInfo: Decodable, Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: String?
    var paused: Bool?
    var time: Double?
    var duration: Double?
    var volume: Double?
    var hasMedia: Bool?
    /// Page clock (ms since 1970) when `time` was read, so the reply's delay doesn't
    /// make the position late.
    var now: Double?
}

enum WebMediaScripts {
    /// Reads Media Session metadata (set by YouTube, YouTube Music, SoundCloud, Spotify
    /// Web and others) plus the playing media element. Uses single quotes only so it
    /// embeds cleanly in an AppleScript string.
    static let readMedia = """
    (function(){var m=navigator.mediaSession&&navigator.mediaSession.metadata;\
    var els=Array.prototype.slice.call(document.querySelectorAll('video,audio'));var el=null;\
    for(var i=0;i<els.length;i++){if(!els[i].paused){el=els[i];break;}}if(!el&&els.length){el=els[0];}\
    var art=null;if(m&&m.artwork&&m.artwork.length){var best=0,bw=-1;for(var j=0;j<m.artwork.length;j++){\
    var w=parseInt((m.artwork[j].sizes||'0x0').split('x')[0])||0;if(w>bw){bw=w;best=j;}}art=m.artwork[best].src;}\
    return JSON.stringify({title:m?m.title:null,artist:m?m.artist:null,album:m?m.album:null,artwork:art,\
    paused:el?el.paused:null,time:el?el.currentTime:null,duration:(el&&isFinite(el.duration))?el.duration:null,\
    volume:el?el.volume:null,hasMedia:!!el,now:Date.now()});})()
    """

    static let playPause = """
    (function(){var els=document.querySelectorAll('video,audio');for(var i=0;i<els.length;i++){\
    if(!els[i].paused){els[i].pause();return 'paused';}}if(els.length){els[0].play();return 'playing';}return 'none';})()
    """

    static let next = """
    (function(){var b=document.querySelector('.ytp-next-button, ytmusic-player-bar .next-button, \
    [data-testid=control-button-skip-forward], .skipControl__next, [aria-label=Next]');\
    if(b){b.click();return 'ok';}return 'none';})()
    """

    static let previous = """
    (function(){var el=document.querySelector('video,audio');if(el&&el.currentTime>3){el.currentTime=0;return 'restart';}\
    var b=document.querySelector('.ytp-prev-button, ytmusic-player-bar .previous-button, \
    [data-testid=control-button-skip-back], .skipControl__previous');\
    if(b&&b.offsetParent!==null){b.click();return 'ok';}if(el){el.currentTime=0;}return 'restart';})()
    """

    static func seek(_ seconds: Double) -> String {
        "(function(){var el=document.querySelector('video,audio');if(el){el.currentTime=\(String(format: "%.2f", max(0, seconds)));}})()"
    }

    static func volume(_ value: Double) -> String {
        "(function(){var els=document.querySelectorAll('video,audio');for(var i=0;i<els.length;i++){els[i].volume=\(String(format: "%.3f", min(max(value, 0), 1)));}})()"
    }

    static func appleScriptLiteral(_ js: String) -> String {
        js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
