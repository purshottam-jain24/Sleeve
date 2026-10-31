import Foundation
import Observation

/// Owns the music providers and decides which one is "active".
@MainActor
@Observable
public final class MusicSourceManager {
    public private(set) var providers: [any MusicProvider]
    public private(set) var active: PlaybackSnapshot?
    /// Bumped whenever any provider's status changes so views can observe it.
    public private(set) var statusRevision = 0

    @ObservationIgnored public var onActiveChange: (@MainActor (PlaybackSnapshot?) -> Void)?
    @ObservationIgnored private var sourceSettings: SourceSettings
    @ObservationIgnored private var isRunning = false

    public init(providers: [any MusicProvider], settings: SourceSettings) {
        self.providers = providers
        self.sourceSettings = settings
        for provider in providers {
            provider.onChange = { [weak self] in self?.providerDidChange() }
        }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        providers.filter { sourceSettings.enabled.contains($0.source) }.forEach { $0.start() }
    }

    public func stop() {
        isRunning = false
        providers.forEach { $0.stop() }
        updateActive()
    }

    public func update(settings: SourceSettings) {
        guard settings != sourceSettings else { return }
        sourceSettings = settings
        guard isRunning else { return }
        for provider in providers {
            if settings.enabled.contains(provider.source) { provider.start() } else { provider.stop() }
        }
        updateActive()
    }

    public func provider(for source: MusicSourceID) -> (any MusicProvider)? {
        providers.first { $0.source == source }
    }

    public var activeProvider: (any MusicProvider)? {
        active.flatMap { provider(for: $0.source) }
    }

    public func perform(_ command: PlaybackCommand) async throws(MusicSourceError) {
        guard let provider = activeProvider else { throw .notRunning }
        try await provider.perform(command)
    }

    public func refreshAll() async {
        for provider in providers where sourceSettings.enabled.contains(provider.source) {
            await provider.refresh()
        }
    }

    private func providerDidChange() {
        statusRevision &+= 1
        updateActive()
    }

    private func updateActive() {
        let candidates = providers
            .filter { isRunning && sourceSettings.enabled.contains($0.source) }
            .compactMap(\.snapshot)
            .filter { $0.state != .stopped && $0.track != nil }
        let next = Self.selectActive(candidates: candidates, previous: active, settings: sourceSettings)
        guard next != active else { return }
        active = next
        onActiveChange?(next)
    }

    /// Playing beats paused; among equals, source priority wins; a paused source that was
    /// already active stays active so the UI does not jump between paused players.
    nonisolated static func selectActive(
        candidates: [PlaybackSnapshot],
        previous: PlaybackSnapshot?,
        settings: SourceSettings
    ) -> PlaybackSnapshot? {
        let byRank = candidates.sorted { settings.rank(of: $0.source) < settings.rank(of: $1.source) }
        if let playing = byRank.first(where: { $0.state == .playing }) {
            return playing
        }
        if let previous, let same = byRank.first(where: { $0.source == previous.source }) {
            return same
        }
        return byRank.first
    }
}
