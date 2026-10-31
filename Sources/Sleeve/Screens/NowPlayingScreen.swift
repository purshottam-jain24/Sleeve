import SleeveCore
import AppKit
import SwiftUI

struct NowPlayingScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let nowPlaying = env.nowPlaying
        ZStack {
            AmbientBackdrop(
                artwork: nowPlaying.artwork,
                palette: nowPlaying.palette,
                identity: nowPlaying.snapshot?.track?.cacheKey
            )
            if let snapshot = nowPlaying.snapshot, let track = snapshot.track {
                // Lyrics get the stage only when there are lyrics to show; otherwise the
                // artwork takes the whole screen instead of a "no lyrics" message.
                let showLyrics = env.settings.settings.lyrics.isEnabled && env.lyrics.document != nil
                GeometryReader { geo in
                    let layout = NowPlayingLayout(size: geo.size, showLyrics: showLyrics)
                    Group {
                        switch layout {
                        case .stage:
                            PlayerColumn(snapshot: snapshot, track: track, centered: true)
                                .frame(maxWidth: min(620, geo.size.width - 2 * layout.margin))
                                .padding(.vertical, layout.margin)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .sideBySide(let column):
                            HStack(alignment: .center, spacing: layout.margin) {
                                PlayerColumn(snapshot: snapshot, track: track, centered: false)
                                    .frame(width: column)
                                LyricsPanel(fontSize: geo.size.width > 1200 ? 28 : 24, compact: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .padding(layout.margin)
                        case .stacked:
                            VStack(spacing: DS.Space.s4) {
                                CompactPlayer(snapshot: snapshot, track: track)
                                LyricsPanel(fontSize: 22, compact: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .padding(layout.margin)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .animation(DS.Motion.smooth, value: layout)
                }
            } else {
                NothingPlayingView()
            }
        }
        .playbackKeyboardShortcuts()
    }
}

/// How Now Playing arranges itself for the space it has (window size, sidebar shown or
/// hidden, full screen).
enum NowPlayingLayout: Equatable {
    /// No lyrics: the artwork is the centrepiece.
    case stage
    /// Player column of the given width beside the lyrics.
    case sideBySide(column: CGFloat)
    /// Narrow: a compact player above the lyrics.
    case stacked

    init(size: CGSize, showLyrics: Bool) {
        if !showLyrics || size.width < 1 {
            self = .stage
        } else if size.width >= 760, size.height >= 460 {
            self = .sideBySide(column: min(420, max(260, size.width * 0.36)))
        } else {
            self = .stacked
        }
    }

    var margin: CGFloat {
        switch self {
        case .stage: 48
        case .sideBySide(let column): column > 340 ? 56 : 36
        case .stacked: 28
        }
    }
}

/// Artwork, track info and controls. The artwork takes whatever space the rest leaves,
/// keeping its own shape (square album art, 16:9 video thumbnails).
private struct PlayerColumn: View {
    @Environment(AppEnvironment.self) private var env
    var snapshot: PlaybackSnapshot
    var track: Track
    var centered: Bool

    var body: some View {
        let nowPlaying = env.nowPlaying
        let aspect = min(max(ArtworkView.aspectRatio(of: nowPlaying.artwork), 1), 16.0 / 9.0)
        let alignment: HorizontalAlignment = centered ? .center : .leading
        VStack(alignment: alignment, spacing: centered ? DS.Space.s8 : DS.Space.s6) {
            ArtworkView(image: nowPlaying.artwork, palette: nowPlaying.palette, cornerRadius: DS.Radius.lg, identity: track.cacheKey)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: centered ? 560 : .infinity, alignment: centered ? .center : .bottomLeading)
                .shadow(color: .black.opacity(0.45), radius: 40, y: 24)
                .scaleEffect(snapshot.state == .playing ? 1 : 0.94)
                .animation(DS.Motion.smooth, value: snapshot.state)
                .animation(DS.Motion.smooth, value: aspect)
                .layoutPriority(-1)

            VStack(alignment: alignment, spacing: DS.Space.s5) {
                VStack(alignment: alignment, spacing: 6) {
                    Text(track.title)
                        .font(centered ? DS.Font.display : DS.Font.heroTitle)
                        .tracking(centered ? DS.Tracking.display : DS.Tracking.heroTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(centered ? .center : .leading)
                        .contentTransition(.opacity)
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(DS.Font.heroSubtitle)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .animation(DS.Motion.smooth, value: track.cacheKey)

                PlaybackControls(snapshot: snapshot, size: .regular)
                    .frame(maxWidth: centered ? 460 : .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Compact row for narrow windows: small artwork, title and controls.
private struct CompactPlayer: View {
    @Environment(AppEnvironment.self) private var env
    var snapshot: PlaybackSnapshot
    var track: Track

    var body: some View {
        let nowPlaying = env.nowPlaying
        let aspect = min(max(ArtworkView.aspectRatio(of: nowPlaying.artwork), 1), 16.0 / 9.0)
        HStack(alignment: .center, spacing: DS.Space.s4) {
            ArtworkView(image: nowPlaying.artwork, palette: nowPlaying.palette, cornerRadius: DS.Radius.md, identity: track.cacheKey)
                .frame(width: 96 * aspect, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 20, weight: .semibold)).tracking(-0.4).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                    if !track.artist.isEmpty {
                        Text(track.artist).font(.system(size: 14)).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
                    }
                }
                PlaybackControls(snapshot: snapshot, size: .compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Progress, transport, volume and where the music is playing.
private struct PlaybackControls: View {
    enum Size { case regular, compact }

    @Environment(AppEnvironment.self) private var env
    var snapshot: PlaybackSnapshot
    var size: Size

    var body: some View {
        let nowPlaying = env.nowPlaying
        let compact = size == .compact
        VStack(spacing: compact ? DS.Space.s2 : DS.Space.s4) {
            ProgressScrubber(snapshot: snapshot, tint: .white) { nowPlaying.perform(.seek($0)) }

            HStack(spacing: DS.Space.s4) {
                if compact {
                    SourceButton(snapshot: snapshot)
                    Spacer(minLength: 0)
                }
                GlassIconButton(systemName: "backward.fill", diameter: compact ? 34 : 46, label: "Previous") { nowPlaying.perform(.previous) }
                GlassIconButton(systemName: snapshot.state == .playing ? "pause.fill" : "play.fill", diameter: compact ? 44 : 62,
                                label: snapshot.state == .playing ? "Pause" : "Play", prominent: true) {
                    nowPlaying.perform(.playPause)
                }
                GlassIconButton(systemName: "forward.fill", diameter: compact ? 34 : 46, label: "Next") { nowPlaying.perform(.next) }
            }
            .disabled(!canControl)
            .opacity(canControl ? 1 : 0.4)
            .frame(maxWidth: .infinity, alignment: compact ? .trailing : .center)

            if !compact {
                if let volume = snapshot.volume, canControl {
                    VolumeSlider(volume: volume) { nowPlaying.perform(.setVolume($0)) }
                        .tint(.white)
                }
                HStack(spacing: DS.Space.s2) {
                    SourceButton(snapshot: snapshot)
                    if let message = permissionMessage {
                        Button("Allow Control…", action: SystemSettingsLinks.openAutomation)
                            .controlSize(.small)
                            .help(message)
                    }
                    if case .limited(.browserScriptingOff(let browser)) = status {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .help("Basic details only. In \(browser), turn on “Allow JavaScript from Apple Events” for progress and controls (see Music Sources).")
                            .accessibilityLabel("Basic details only")
                    }
                }
            }
        }
    }

    private var status: ProviderStatus? {
        _ = env.sources.statusRevision
        return env.sources.activeProvider?.status
    }

    private var canControl: Bool {
        if case .limited(.automationDenied) = status { return false }
        return snapshot.supportsControl
    }

    private var permissionMessage: String? {
        if case .limited(.automationDenied) = status {
            return "Allow Sleeve to control \(snapshot.displayPlayerName) in System Settings › Privacy & Security › Automation to enable controls and artwork."
        }
        return nil
    }
}

/// Shows which app is playing; clicking brings that app (and browser tab) forward.
struct SourceButton: View {
    @Environment(AppEnvironment.self) private var env
    var snapshot: PlaybackSnapshot
    @State private var hovering = false

    var body: some View {
        Button {
            env.sources.provider(for: snapshot.source)?.revealPlayer()
        } label: {
            HStack(spacing: 6) {
                AppIcon(bundleIdentifier: snapshot.displayPlayerBundleIdentifier, size: 14)
                Text("Playing in \(snapshot.displayPlayerName)")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(hovering ? DS.Palette.textPrimary : DS.Palette.textTertiary)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DS.Motion.snappy, value: hovering)
        .help("Show in \(snapshot.displayPlayerName)")
    }
}

struct AppIcon: View {
    var bundleIdentifier: String?
    var size: CGFloat

    var body: some View {
        if let bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "globe")
                .font(.system(size: size * 0.7, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: size, height: size)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: size * 0.22))
        }
    }
}

struct NothingPlayingView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: DS.Space.s5) {
            ZStack {
                Circle().fill(.white.opacity(0.06)).frame(width: 120, height: 120)
                Image(systemName: "waveform")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            VStack(spacing: 6) {
                Text("Nothing playing").font(DS.Font.heroTitle).tracking(DS.Tracking.heroTitle)
                Text(env.settings.settings.general.autoDetectMusic
                     ? "Start a song in Spotify, Music or YouTube and it appears here instantly."
                     : "Music detection is off. Turn it on in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: DS.Space.s3) {
                ForEach(MusicSourceID.allCases) { source in
                    if let bundleID = source.bundleIdentifier, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                        Button {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                        } label: {
                            HStack(spacing: 8) {
                                AppIcon(bundleIdentifier: source.bundleIdentifier, size: 20)
                                Text("Open \(source.displayName)")
                            }
                        }
                        .buttonStyle(.quiet)
                    }
                }
            }
            .padding(.top, DS.Space.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Space toggles playback; ⌘←/⌘→ live in the Playback menu.
    func playbackKeyboardShortcuts() -> some View {
        modifier(PlaybackKeys())
    }
}

private struct PlaybackKeys: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.space) {
                env.nowPlaying.perform(.playPause)
                return .handled
            }
            .onAppear { focused = true }
    }
}
