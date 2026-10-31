import SleeveAudio
import SleeveCore
import SleeveWallpaper
import SwiftUI

struct MenuBarLabel: View {
    var nowPlaying: NowPlayingService

    var body: some View {
        Image(systemName: nowPlaying.isPlaying ? "waveform" : "music.note")
            .accessibilityLabel("Sleeve")
    }
}

/// The compact control panel shown from the menu bar icon.
struct MenuBarPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            NowPlayingSection().panelCard()
            GlowQuickControls().panelCard()
            WallpaperQuickControls().panelCard()
            footer
                .padding(.horizontal, DS.Space.s2)
                .padding(.top, 2)
        }
        .padding(DS.Space.s2)
        .frame(width: 340)
        .preferredColorScheme(.dark)
        .tint(DS.Palette.accent)
    }

    @Environment(\.openWindow) private var openWindow

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: MainWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Sleeve", systemImage: "macwindow")
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .foregroundStyle(DS.Palette.textSecondary)
    }
}

private struct NowPlayingSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let nowPlaying = env.nowPlaying
        if let snapshot = nowPlaying.snapshot, let track = snapshot.track {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: DS.Space.s3) {
                    ArtworkView(image: nowPlaying.artwork, palette: nowPlaying.palette, identity: track.cacheKey)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(DS.Font.title).lineLimit(1)
                        Text(track.artist).font(DS.Font.subtitle).foregroundStyle(.secondary).lineLimit(1)
                        Label(snapshot.displayPlayerName, systemImage: snapshot.source == .web ? "globe" : "music.note")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                ProgressScrubber(snapshot: snapshot, tint: nowPlaying.palette.primary.color) {
                    nowPlaying.perform(.seek($0))
                }
                HStack {
                    TransportControls(isPlaying: snapshot.state == .playing, isEnabled: canControl) {
                        nowPlaying.perform($0)
                    }
                    Spacer()
                    if let volume = snapshot.volume, canControl {
                        VolumeSlider(volume: volume) { nowPlaying.perform(.setVolume($0)) }
                            .frame(width: 110)
                    }
                }
                if let message = permissionMessage {
                    PermissionNotice(message: message, action: "Open Automation Settings", perform: SystemSettingsLinks.openAutomation)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Nothing playing").font(DS.Font.title)
                Text(emptyHint).font(DS.Font.subtitle).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activeStatus: ProviderStatus? {
        _ = env.sources.statusRevision
        return env.sources.activeProvider?.status
    }

    private var canControl: Bool {
        if case .limited(.automationDenied) = activeStatus { return false }
        return env.nowPlaying.snapshot?.supportsControl ?? false
    }

    private var permissionMessage: String? {
        if case .limited(.automationDenied) = activeStatus {
            return "Allow Sleeve to control \(env.nowPlaying.snapshot?.source.displayName ?? "the player") to enable controls and artwork."
        }
        return nil
    }

    private var emptyHint: String {
        env.settings.settings.general.autoDetectMusic
            ? "Play something in Spotify, Music or your browser."
            : "Music detection is turned off in Settings."
    }
}

private struct GlowQuickControls: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Toggle(isOn: $settings.settings.glow.isEnabled) {
                PanelTitle(title: "Edge Glow", symbol: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if settings.settings.glow.isEnabled {
                Picker("Preset", selection: $settings.settings.glow.style.preset) {
                    ForEach(GlowPreset.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                Toggle("Follow the beat", isOn: $settings.settings.glow.followBeat)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 12))
                    .help("Listens to system audio to sync the glow. Off: no audio is captured.")
                if settings.settings.glow.followBeat {
                    AudioStatusRow(state: env.audio.state, preset: settings.settings.glow.style.preset, waitingForPermission: env.audio.isWaitingForPermission)
                }
            }
        }
    }
}

struct AudioStatusRow: View {
    var state: AudioCaptureState
    var preset: GlowPreset
    var waitingForPermission = false

    var body: some View {
        if preset.usesAudio {
            switch state {
            case .failed(let reason):
                PermissionNotice(
                    message: "System audio isn't available, so the glow can't react to music. \(reason)",
                    action: "Open Privacy Settings",
                    perform: SystemSettingsLinks.openAudioCapture
                )
            case .running(let backend):
                Label("Listening to system audio", systemImage: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Using \(backend.rawValue). Audio is analysed in memory, never recorded.")
            case .starting where waitingForPermission:
                PermissionNotice(
                    message: "Waiting for permission to hear system audio. Look for a macOS prompt, or allow Sleeve under Screen & System Audio Recording.",
                    action: "Open Privacy Settings",
                    perform: SystemSettingsLinks.openAudioCapture
                )
            case .starting:
                Label("Starting audio…", systemImage: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            }
        }
    }
}

private extension View {
    /// A section of the menu bar panel: the app's card surface, flat (the panel itself
    /// already floats).
    func panelCard() -> some View {
        padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: DS.Radius.lg, shadow: false)
    }
}

/// Icon tile and title, used as the label of a panel section's main switch.
private struct PanelTitle: View {
    var title: String
    var symbol: String

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            IconTile(symbol: symbol, size: 22)
            Text(title).font(DS.Font.cardTitle).foregroundStyle(DS.Palette.textPrimary)
        }
    }
}

struct PermissionNotice: View {
    var message: String
    var action: String
    var perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform)
                .controlSize(.small)
        }
        .padding(DS.Space.s2)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: DS.Radius.sm))
    }
}

private struct WallpaperQuickControls: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = env.settings
        let wallpaper = env.wallpaper
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            PanelTitle(title: "Wallpaper", symbol: "photo.on.rectangle")
            if let video = wallpaper.activeVideo {
                HStack(spacing: DS.Space.s2) {
                    Text(video.name)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button(wallpaper.isPaused ? "Resume" : "Pause") { wallpaper.isPaused.toggle() }
                    Button("Turn Off") { wallpaper.stopVideo() }
                }
                .buttonStyle(.quiet)
            } else {
                Button("Choose a live wallpaper…") {
                    env.section = .wallpaper
                    openWindow(id: MainWindow.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.quiet)
            }
            Toggle("Artwork on lock screen", isOn: $settings.settings.wallpaper.artworkOnLockScreen)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
        }
    }
}
