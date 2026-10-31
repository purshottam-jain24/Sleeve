import Foundation

public struct LyricWord: Codable, Sendable, Equatable {
    public var time: TimeInterval
    public var text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public struct LyricLine: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var time: TimeInterval
    public var text: String
    /// Word timings when the source provides enhanced LRC; otherwise empty.
    public var words: [LyricWord]

    public init(id: Int, time: TimeInterval, text: String, words: [LyricWord] = []) {
        self.id = id
        self.time = time
        self.text = text
        self.words = words
    }

    /// Empty lines in LRC mark instrumental gaps.
    public var isGap: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Lyrics exactly as retrieved from a source. Never synthesised.
public struct LyricsDocument: Codable, Sendable, Equatable {
    public var synced: [LyricLine]
    public var plain: [String]
    public var sourceName: String
    /// Source-side identifier, used to remember manual picks.
    public var sourceID: String?

    public init(synced: [LyricLine], plain: [String], sourceName: String, sourceID: String? = nil) {
        self.synced = synced
        self.plain = plain
        self.sourceName = sourceName
        self.sourceID = sourceID
    }

    public var isSynced: Bool { !synced.isEmpty }

    /// Index of the line being sung at `position`, or `nil` before the first line.
    public func lineIndex(at position: TimeInterval) -> Int? {
        guard let first = synced.first, position >= first.time else { return nil }
        var low = 0, high = synced.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if synced[mid].time <= position { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// 0...1 progress through line `index`, measured against the next line's start.
    public func progress(ofLine index: Int, at position: TimeInterval, trackDuration: TimeInterval?) -> Double {
        guard synced.indices.contains(index) else { return 0 }
        let start = synced[index].time
        let end = index + 1 < synced.count
            ? synced[index + 1].time
            : max(start + 4, trackDuration ?? start + 4)
        guard end > start else { return 1 }
        return min(max((position - start) / (end - start), 0), 1)
    }
}

public enum LyricsResult: Codable, Sendable, Equatable {
    case found(LyricsDocument)
    case instrumental
    case notFound
}

public struct LyricsCandidate: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval?
    public var hasSynced: Bool
    public var result: LyricsResult

    public init(id: String, title: String, artist: String, album: String, duration: TimeInterval?, hasSynced: Bool, result: LyricsResult) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.hasSynced = hasSynced
        self.result = result
    }
}

public protocol LyricsProvider: Sendable {
    var name: String { get }
    func lyrics(title: String, artist: String, album: String, duration: TimeInterval?) async throws -> LyricsResult
    func search(query: String) async throws -> [LyricsCandidate]
}
