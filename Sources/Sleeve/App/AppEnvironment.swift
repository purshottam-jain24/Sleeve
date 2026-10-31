import AfterglowAudio
import AfterglowCore
import AfterglowGlow
import AppKit
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case nowPlaying, lyrics, glow, sources, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .lyrics: "Lyrics"
        case .glow: "Edge Glow"
        case .sources: "Music Sources"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "play.circle"
        case .lyrics: "quote.bubble"
        case .glow: "sparkles"
        case .sources: "music.note.list"
        case .settings: "gearshape"
        }
    }
}

/// Composition root: creates every service once and wires them together.
@MainActor
@Observable
final class AppEnvironment {
    let settings: SettingsManager
    let sources: MusicSourceManager
    let nowPlaying: NowPlayingService
    let audio: AudioCaptureService
    let stream: AudioFeatureStream
    let lyrics: LyricsService
    let launchAtLogin = LaunchAtLogin()
    var section: AppSection = .nowPlaying

    @ObservationIgnored let glow: EdgeGlowRenderer
    private(set) var isAsleep = false
    @ObservationIgnored private var powerObservers: [NSObjectProtocol] = []

    init(settings: SettingsManager = SettingsManager()) {
        self.settings = settings
        let providers: [any MusicProvider] = [SpotifyService(), AppleMusicService()]
        sources = MusicSourceManager(providers: providers, settings: settings.settings.sources)
        nowPlaying = NowPlayingService(sources: sources)
        audio = AudioCaptureService()
        stream = AudioFeatureStream(audio: audio)
        glow = EdgeGlowRenderer(stream: stream)
        lyrics = LyricsService()

        observePower()
        bind()
    }

    /// Re-applies settings and playback state to the services whenever anything they
    /// depend on changes (Observation re-arms the tracking after each change).
    private func bind() {
        withObservationTracking {
            let current = settings.settings
            let palette = nowPlaying.palette
            let playing = nowPlaying.isPlaying
            let track = nowPlaying.snapshot?.track
            let previews = stream.previewClients
            let asleep = isAsleep

            if current.general.autoDetectMusic {
                sources.update(settings: current.sources)
                sources.start()
            } else {
                sources.stop()
            }

            let style = current.glow.style
            stream.tuning = AnalyzerTuning(
                sensitivity: Float(style.audioSensitivity),
                bassSensitivity: Float(style.bassSensitivity),
                responseSpeed: Float(style.responseSpeed)
            )
            glow.update(settings: current.glow, palette: palette, isPlaying: playing)
            // Capture only when something will use it: the on-screen glow while music plays
            // (or always, if the user opted into all apps' audio), or a visible preview.
            let listening = playing || current.glow.reactToAllAudio
            let glowNeedsAudio = current.glow.isEnabled && style.preset.usesAudio && listening
            audio.setActive(!asleep && (glowNeedsAudio || previews > 0))

            if current.lyrics.isEnabled {
                lyrics.update(for: track)
            } else {
                lyrics.clear()
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.bind() }
        }
    }

    /// Glow colours as currently configured (artwork palette or manual).
    var glowColors: [RGBAColor] {
        let style = settings.settings.glow.style
        return style.useArtworkColors ? nowPlaying.palette.glowColors : [style.primaryColor, style.secondaryColor]
    }

    /// Playback position adjusted by the lyrics offset for the current track.
    func lyricsPosition(at date: Date = Date()) -> TimeInterval? {
        guard let position = nowPlaying.position(at: date) else { return nil }
        return position + settings.settings.lyrics.offset(for: nowPlaying.snapshot?.track)
    }

    private func observePower() {
        let center = NSWorkspace.shared.notificationCenter
        powerObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isAsleep = true }
        })
        powerObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isAsleep = false
                Task { await self.sources.refreshAll() }
            }
        })
    }

    func shutdown() {
        audio.setActive(false)
        settings.saveNow()
    }
}
