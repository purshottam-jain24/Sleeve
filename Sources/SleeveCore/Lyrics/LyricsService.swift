import CryptoKit
import Foundation
import Observation

/// Fetches, caches and serves lyrics for the current track.
@MainActor
@Observable
public final class LyricsService {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case loaded(LyricsDocument)
        case instrumental
        case notFound
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var track: Track?
    public private(set) var candidates: [LyricsCandidate] = []
    public private(set) var isSearching = false
    public private(set) var searchError: String?

    @ObservationIgnored private let provider: any LyricsProvider
    @ObservationIgnored private let cache: LyricsCache
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Automatic retries left for the current track after a failure (service busy, offline).
    @ObservationIgnored private var autoRetriesLeft = 3

    public init(provider: any LyricsProvider = LRCLibProvider(), cache: LyricsCache = LyricsCache()) {
        self.provider = provider
        self.cache = cache
    }

    public var providerName: String { provider.name }

    public var document: LyricsDocument? {
        if case .loaded(let document) = state { return document }
        return nil
    }

    /// Loads lyrics when the track changes. Calling with the same track is a no-op.
    public func update(for track: Track?) {
        guard track?.cacheKey != self.track?.cacheKey else { return }
        self.track = track
        autoRetriesLeft = 3
        candidates = []
        searchError = nil
        load(force: false)
    }

    #if DEBUG
    /// Layout snapshots only: shows the given state without fetching.
    public func debugShow(_ state: State) {
        loadTask?.cancel()
        autoRetriesLeft = 0
        self.state = state
    }
    #endif

    public func retry() {
        load(force: true)
    }

    public func clear() {
        loadTask?.cancel()
        track = nil
        state = .idle
    }

    private func load(force: Bool) {
        loadTask?.cancel()
        guard let track else {
            state = .idle
            return
        }
        if !force, let cached = cache.result(for: track) {
            apply(cached)
            return
        }
        state = .loading
        let provider = provider
        let cache = cache
        loadTask = Task { [weak self] in
            do {
                let result = try await provider.lyrics(
                    title: track.title, artist: track.artist, album: track.album, duration: track.duration
                )
                guard !Task.isCancelled else { return }
                cache.store(result, for: track)
                self?.apply(result)
            } catch {
                guard !Task.isCancelled, let self else { return }
                let code = (error as? URLError)?.code
                let message = switch code {
                case .notConnectedToInternet: "You're offline. Lyrics will load when you reconnect."
                case .resourceUnavailable: "\(self.providerName) is busy right now. Trying again shortly."
                default: "Couldn't reach \(self.providerName). Trying again shortly."
                }
                self.state = .failed(message)
                guard self.autoRetriesLeft > 0 else { return }
                self.autoRetriesLeft -= 1
                let delay = Double(3 - self.autoRetriesLeft) * 20
                self.loadTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, self?.track?.cacheKey == track.cacheKey else { return }
                    self?.load(force: true)
                }
            }
        }
    }

    private func apply(_ result: LyricsResult) {
        switch result {
        case .found(let document): state = .loaded(document)
        case .instrumental: state = .instrumental
        case .notFound: state = .notFound
        }
    }

    // MARK: Manual search

    public func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            candidates = try await provider.search(query: query)
            if candidates.isEmpty { searchError = "No matches for “\(query)”." }
        } catch {
            candidates = []
            searchError = "Search failed. Check your connection and try again."
        }
    }

    /// Uses a manually chosen result for the current track and remembers it.
    public func choose(_ candidate: LyricsCandidate) {
        guard let track else { return }
        loadTask?.cancel()
        cache.store(candidate.result, for: track)
        apply(candidate.result)
        candidates = []
    }
}

/// Small on-disk cache in ~/Library/Caches. "Not found" entries expire after a day so
/// newly contributed lyrics are picked up.
public final class LyricsCache: Sendable {
    private let directory: URL?

    public init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        // v2: matching became stricter; drop results cached by the looser rules.
        .appendingPathComponent("app.sleeve/lyrics-v2", isDirectory: true)) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private struct Entry: Codable {
        var result: LyricsResult
        var date: Date
    }

    private func url(for track: Track) -> URL? {
        let key = "\(track.artist)\u{1F}\(track.title)\u{1F}\(track.album)\u{1F}\(Int(track.duration ?? 0))"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent("\(digest.prefix(32)).json")
    }

    public func result(for track: Track) -> LyricsResult? {
        guard let url = url(for: track),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        if entry.result == .notFound, Date().timeIntervalSince(entry.date) > 86_400 { return nil }
        return entry.result
    }

    public func store(_ result: LyricsResult, for track: Track) {
        guard let url = url(for: track),
              let data = try? JSONEncoder().encode(Entry(result: result, date: Date())) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
