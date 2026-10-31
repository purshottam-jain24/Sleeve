import AfterglowAudio
import AfterglowCore
import SwiftUI

struct MenuBarLabel: View {
    var nowPlaying: NowPlayingService

    var body: some View {
        Image(systemName: nowPlaying.isPlaying ? "waveform" : "music.note")
            .accessibilityLabel("Afterglow")
    }
}

/// The compact control panel shown from the menu bar icon.
struct MenuBarPanel: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            NowPlayingSection()
            Divider()
            GlowQuickControls()
            Divider()
            footer
        }
        .padding(DS.Space.s4)
        .frame(width: 320)
    }

    @Environment(\.openWindow) private var openWindow

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: MainWindow.id)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Afterglow", systemImage: "macwindow")
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
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
                        Label(snapshot.source.displayName, systemImage: snapshot.source == .spotify ? "dot.radiowaves.left.and.right" : "music.note")
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
        return true
    }

    private var permissionMessage: String? {
        if case .limited(.automationDenied) = activeStatus {
            return "Allow Afterglow to control \(env.nowPlaying.snapshot?.source.displayName ?? "the player") to enable controls and artwork."
        }
        return nil
    }

    private var emptyHint: String {
        env.settings.settings.general.autoDetectMusic
            ? "Play something in Spotify or Music."
            : "Music detection is turned off in Settings."
    }
}

private struct GlowQuickControls: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Toggle(isOn: $settings.settings.glow.isEnabled) {
                Label("Edge Glow", systemImage: "rectangle.dashed")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if settings.settings.glow.isEnabled {
                Picker("Preset", selection: $settings.settings.glow.style.preset) {
                    ForEach(GlowPreset.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)

                AudioStatusRow(state: env.audio.state, preset: settings.settings.glow.style.preset, waitingForPermission: env.audio.isWaitingForPermission)
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
                Label("Reacting to system audio (\(backend.rawValue))", systemImage: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .starting where waitingForPermission:
                PermissionNotice(
                    message: "Waiting for permission to hear system audio. Look for a macOS prompt, or allow Afterglow under Screen & System Audio Recording.",
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
