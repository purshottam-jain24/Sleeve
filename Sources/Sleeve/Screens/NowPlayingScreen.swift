import AfterglowCore
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
                GeometryReader { geo in
                    let artSize = min(380, max(240, min(geo.size.height * 0.48, geo.size.width * 0.32)))
                    HStack(alignment: .center, spacing: 56) {
                        PlayerColumn(snapshot: snapshot, track: track, artSize: artSize)
                            .frame(width: artSize)
                        if env.settings.settings.lyrics.isEnabled {
                            LyricsPanel(fontSize: 26, compact: true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 56)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                NothingPlayingView()
            }
        }
        .playbackKeyboardShortcuts()
    }
}

private struct PlayerColumn: View {
    @Environment(AppEnvironment.self) private var env
    var snapshot: PlaybackSnapshot
    var track: Track
    var artSize: CGFloat

    var body: some View {
        let nowPlaying = env.nowPlaying
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            ArtworkView(image: nowPlaying.artwork, palette: nowPlaying.palette, cornerRadius: DS.Radius.lg, identity: track.cacheKey)
                .frame(width: artSize, height: artSize)
                .shadow(color: .black.opacity(0.45), radius: 40, y: 24)
                .scaleEffect(snapshot.state == .playing ? 1 : 0.94)
                .animation(DS.Motion.smooth, value: snapshot.state)

            VStack(alignment: .leading, spacing: 6) {
                Text(track.title)
                    .font(DS.Font.heroTitle)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Text(track.artist)
                    .font(DS.Font.heroSubtitle)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .animation(DS.Motion.smooth, value: track.cacheKey)

            ProgressScrubber(snapshot: snapshot, tint: .white) { nowPlaying.perform(.seek($0)) }

            HStack(spacing: DS.Space.s4) {
                GlassIconButton(systemName: "backward.fill", diameter: 46, label: "Previous") { nowPlaying.perform(.previous) }
                GlassIconButton(systemName: snapshot.state == .playing ? "pause.fill" : "play.fill", diameter: 62,
                                label: snapshot.state == .playing ? "Pause" : "Play", prominent: true) {
                    nowPlaying.perform(.playPause)
                }
                GlassIconButton(systemName: "forward.fill", diameter: 46, label: "Next") { nowPlaying.perform(.next) }
            }
            .disabled(!canControl)
            .opacity(canControl ? 1 : 0.4)
            .frame(maxWidth: .infinity)

            if let volume = snapshot.volume, canControl {
                VolumeSlider(volume: volume) { nowPlaying.perform(.setVolume($0)) }
                    .tint(.white)
            }

            HStack(spacing: DS.Space.s2) {
                SourceButton(source: snapshot.source)
                if let message = permissionMessage {
                    Button("Allow Control…", action: SystemSettingsLinks.openAutomation)
                        .controlSize(.small)
                        .help(message)
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
        return true
    }

    private var permissionMessage: String? {
        canControl ? nil : "Allow Afterglow to control \(snapshot.source.displayName) in System Settings › Privacy & Security › Automation to enable controls and artwork."
    }
}

/// Shows which app is playing; clicking brings that app forward.
struct SourceButton: View {
    var source: MusicSourceID

    var body: some View {
        Button {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        } label: {
            HStack(spacing: 6) {
                AppIcon(bundleIdentifier: source.bundleIdentifier, size: 16)
                Text("Playing in \(source.displayName)")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Open \(source.displayName)")
    }
}

struct AppIcon: View {
    var bundleIdentifier: String
    var size: CGFloat

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").frame(width: size, height: size)
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
                Text("Nothing playing").font(DS.Font.heroTitle)
                Text(env.settings.settings.general.autoDetectMusic
                     ? "Start a song in Spotify or Music and it appears here instantly."
                     : "Music detection is off. Turn it on in Settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: DS.Space.s3) {
                ForEach(MusicSourceID.allCases) { source in
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil {
                        Button {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            }
                        } label: {
                            HStack(spacing: 8) {
                                AppIcon(bundleIdentifier: source.bundleIdentifier, size: 20)
                                Text("Open \(source.displayName)")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.09), in: .capsule)
                        }
                        .buttonStyle(PressableButtonStyle())
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
