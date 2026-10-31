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
        // 1. Exact signature lookup (LRCLIB matches duration within ±2 s).
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
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
        return .notFound
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
        request.setValue("Afterglow/0.2 (macOS music companion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
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

    /// Picks the most plausible candidate; rejects anything whose duration is far off.
    public static func best<T>(_ candidates: [(T, Candidate)], title: String, artist: String, duration: TimeInterval?) -> T? {
        let wantTitle = normalise(cleanTitle(title))
        let wantArtist = normalise(primaryArtist(artist))
        let scored = candidates.compactMap { item, c -> (T, Double)? in
            var score = 0.0
            if let duration, let d = c.duration {
                let delta = abs(d - duration)
                if delta > 8 { return nil }
                score += 3 - delta / 3
            }
            let title = normalise(cleanTitle(c.title))
            if title == wantTitle { score += 4 } else if title.contains(wantTitle) || wantTitle.contains(title) { score += 2 } else { return nil }
            let artist = normalise(c.artist)
            if artist.contains(wantArtist) || wantArtist.contains(artist) { score += 3 }
            if c.hasSynced { score += 2 }
            return (item, score)
        }
        return scored.max { $0.1 < $1.1 }?.0
    }
}
