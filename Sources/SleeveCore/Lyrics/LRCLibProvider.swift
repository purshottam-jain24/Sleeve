import Foundation

/// LRCLIB (https://lrclib.net): free, keyless, community-maintained synced lyrics.
public struct LRCLibProvider: LyricsProvider {
    public let name = "LRCLIB"
    private let session: URLSession
    private let base = URL(string: "https://lrclib.net/api")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    struct Record: Decodable {
        var id: Int
        var trackName: String?
        var artistName: String?
        var albumName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    public func lyrics(title: String, artist: String, album: String, duration: TimeInterval?) async throws -> LyricsResult {
        // Without an artist (e.g. a browser tab title), the exact lookup is rejected.
        if artist.trimmingCharacters(in: .whitespaces).isEmpty {
            return try await titleOnly(title, artistHint: "", duration: duration)
        }

        // 1. Exact signature lookup (LRCLIB matches duration within ±2 s).
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration, duration >= 1 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        if let record: Record = try await get("get", items), let result = Self.result(from: record) {
            return result
        }

        // 2. Search with a cleaned title ("Song - Remastered 2011" → "Song") and pick the best match.
        let cleaned = LyricsMatching.cleanTitle(title)
        let records: [Record] = try await get("search", [
            URLQueryItem(name: "track_name", value: cleaned),
            URLQueryItem(name: "artist_name", value: LyricsMatching.primaryArtist(artist)),
        ]) ?? []
        let best = LyricsMatching.best(
            records.map { ($0, LyricsMatching.Candidate(title: $0.trackName ?? "", artist: $0.artistName ?? "", duration: $0.duration, hasSynced: $0.syncedLyrics?.isEmpty == false)) },
            title: cleaned, artist: artist, duration: duration
        )
        if let best, let result = Self.result(from: best) {
            return result
        }
        // 3. The "artist" may really be a label or uploader (common for web videos).
        return try await titleOnly(title, artistHint: artist, duration: duration)
    }

    /// Searches by title alone. Only trusts a song whose artist overlaps the hint or whose
    /// length matches; never a same-named song by someone else.
    private func titleOnly(_ title: String, artistHint: String, duration: TimeInterval?) async throws -> LyricsResult {
        // Nothing to check a title-only match against.
        guard !artistHint.trimmingCharacters(in: .whitespaces).isEmpty || duration != nil else { return .notFound }
        let cleaned = LyricsMatching.cleanTitle(title)
        guard !cleaned.isEmpty else { return .notFound }
        let records: [Record] = try await get("search", [URLQueryItem(name: "q", value: cleaned)]) ?? []
        let best = LyricsMatching.unambiguous(
            records.map { ($0, LyricsMatching.Candidate(title: $0.trackName ?? "", artist: $0.artistName ?? "", duration: $0.duration, hasSynced: $0.syncedLyrics?.isEmpty == false)) },
            title: cleaned, artistHint: artistHint, duration: duration
        )
        return best.flatMap(Self.result(from:)) ?? .notFound
    }

    public func search(query: String) async throws -> [LyricsCandidate] {
        let records: [Record] = try await get("search", [URLQueryItem(name: "q", value: query)]) ?? []
        return records.prefix(20).compactMap { record in
            guard let result = Self.result(from: record) else { return nil }
            return LyricsCandidate(
                id: "lrclib:\(record.id)",
                title: record.trackName ?? "",
                artist: record.artistName ?? "",
                album: record.albumName ?? "",
                duration: record.duration,
                hasSynced: record.syncedLyrics?.isEmpty == false,
                result: result
            )
        }
    }

    static func result(from record: Record) -> LyricsResult? {
        if record.instrumental == true { return .instrumental }
        let synced = record.syncedLyrics.map(LRCParser.parse) ?? []
        let plain = (record.plainLyrics ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !synced.isEmpty || plain.contains(where: { !$0.isEmpty }) else { return nil }
        return .found(LyricsDocument(synced: synced, plain: plain, sourceName: "LRCLIB", sourceID: "lrclib:\(record.id)"))
    }

    private func get<T: Decodable>(_ path: String, _ items: [URLQueryItem]) async throws -> T? {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items
        var request = URLRequest(url: components.url!, timeoutInterval: 12)
        // LRCLIB asks clients to identify themselves.
        request.setValue("Sleeve/0.2 (macOS music companion)", forHTTPHeaderField: "User-Agent")
        let backoff: [Double] = [1.5, 4]
        for attempt in 0...backoff.count {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300: return try JSONDecoder().decode(T.self, from: data)
            // 400 means LRCLIB rejected the signature (e.g. a missing field): nothing to find.
            case 400, 404: return nil
            // LRCLIB answers 503 "server busy" in bursts; short retries usually succeed.
            case 429, 500...599:
                guard attempt < backoff.count else { throw URLError(.resourceUnavailable) }
                try await Task.sleep(for: .seconds(backoff[attempt]))
            default: throw URLError(.badServerResponse)
            }
        }
        throw URLError(.badServerResponse)
    }
}

/// Title/artist normalisation and candidate scoring, shared by providers.
public enum LyricsMatching {
    public struct Candidate {
        public var title: String
        public var artist: String
        public var duration: TimeInterval?
        public var hasSynced: Bool
    }

    public static func cleanTitle(_ title: String) -> String {
        var t = title
        // "Song - Remastered 2011", "Song - Live at …", "Song - Radio Edit"
        if let dash = t.range(of: " - ") { t = String(t[..<dash.lowerBound]) }
        // "Song (feat. X)", "Song [Remastered]"
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let start = t.range(of: open), let end = t.range(of: close, range: start.upperBound..<t.endIndex) {
                let inner = t[start.upperBound..<end.lowerBound].lowercased()
                let noise = ["feat", "ft.", "with ", "remaster", "live", "version", "edit", "mono", "stereo", "deluxe", "bonus"]
                guard noise.contains(where: inner.contains) else { break }
                t.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    public static func primaryArtist(_ artist: String) -> String {
        for separator in [", ", " & ", " feat. ", " ft. ", " x "] {
            if let range = artist.range(of: separator, options: .caseInsensitive) {
                return String(artist[..<range.lowerBound])
            }
        }
        return artist
    }

    static func normalise(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Words that identify an artist ("Hamza Malik x Zain Zohaib" → hamza, malik, zain, zohaib).
    static func artistTokens(_ artist: String) -> Set<String> {
        let folded = artist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let ignored: Set<String> = ["the", "and", "feat", "with", "music", "official", "records", "topic", "vevo"]
        return Set(folded.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !ignored.contains($0) })
    }

    /// Same artist, or a shared name (features, collaborations, "Artist - Topic").
    public static func artistMatches(_ candidate: String, _ wanted: String) -> Bool {
        let a = normalise(candidate), b = normalise(wanted)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b || a.contains(b) || b.contains(a) { return true }
        return !artistTokens(candidate).isDisjoint(with: artistTokens(wanted))
    }

    /// Title-only matching (the artist we have may be a channel or label): an exact-title
    /// candidate whose artist overlaps the hint, or whose length matches within 3 s.
    public static func unambiguous<T>(_ candidates: [(T, Candidate)], title: String, artistHint: String, duration: TimeInterval?) -> T? {
        let wantTitle = normalise(cleanTitle(title))
        let trusted = candidates.filter { _, c in
            guard normalise(cleanTitle(c.title)) == wantTitle else { return false }
            if artistMatches(c.artist, artistHint) { return true }
            if let duration, let d = c.duration { return abs(d - duration) <= 3 }
            return false
        }
        // Several different artists still fit: don't guess.
        let artists = Set(trusted.map { normalise(primaryArtist($0.1.artist)) })
        guard artists.count == 1 else { return nil }
        return best(trusted, title: title, artist: trusted[0].1.artist, duration: duration)
    }

    /// Picks the most plausible candidate. A candidate must have the right title and either
    /// the right artist or (when both lengths are known) the same length; anything whose
    /// length is far off is rejected.
    public static func best<T>(_ candidates: [(T, Candidate)], title: String, artist: String, duration: TimeInterval?) -> T? {
        let wantTitle = normalise(cleanTitle(title))
        let scored = candidates.compactMap { item, c -> (T, Double)? in
            var score = 0.0
            var lengthMatches = false
            if let duration, let d = c.duration {
                let delta = abs(d - duration)
                if delta > 8 { return nil }
                lengthMatches = delta <= 2
                score += 3 - delta / 3
            }
            let title = normalise(cleanTitle(c.title))
            if title == wantTitle { score += 4 } else if title.contains(wantTitle) || wantTitle.contains(title) { score += 2 } else { return nil }
            let sameArtist = artistMatches(c.artist, artist)
            guard sameArtist || lengthMatches else { return nil }
            if sameArtist { score += 3 }
            if c.hasSynced { score += 2 }
            return (item, score)
        }
        return scored.max { $0.1 < $1.1 }?.0
    }
}
