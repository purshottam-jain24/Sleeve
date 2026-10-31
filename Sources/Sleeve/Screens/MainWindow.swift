import AfterglowCore
import SwiftUI

struct MainWindow: View {
    static let id = "main"

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var env = env
        NavigationSplitView {
            Sidebar(selection: $env.section)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detail
                .toolbarBackground(.hidden, for: .windowToolbar)
                .navigationTitle("")
        }
        .preferredColorScheme(.dark)
        .onAppear {
            (NSApp.delegate as? AppDelegate)?.openMainWindow = { openWindow(id: MainWindow.id) }
        }
    }

    @ViewBuilder private var detail: some View {
        switch env.section {
        case .nowPlaying: NowPlayingScreen()
        case .lyrics: LyricsScreen()
        case .glow: GlowStudioScreen()
        case .sources: SourcesScreen()
        case .settings: SettingsScreen()
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: AppSection
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { selection }, set: { if let s = $0 { selection = s } })) {
                Section {
                    ForEach([AppSection.nowPlaying, .lyrics, .glow]) { section in
                        row(section)
                    }
                }
                Section("Library") {
                    row(.sources)
                    row(.settings)
                }
            }
            .listStyle(.sidebar)

            SidebarNowPlaying()
                .padding(DS.Space.s3)
        }
    }

    private func row(_ section: AppSection) -> some View {
        Label {
            HStack {
                Text(section.title)
                Spacer()
                if section == .glow, env.settings.settings.glow.isEnabled {
                    Circle().fill(.green).frame(width: 6, height: 6)
                        .accessibilityLabel("Edge Glow on")
                }
            }
        } icon: {
            Image(systemName: section.symbol)
        }
        .tag(section)
    }
}

/// Compact player pinned to the bottom of the sidebar.
private struct SidebarNowPlaying: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let nowPlaying = env.nowPlaying
        if let snapshot = nowPlaying.snapshot, let track = snapshot.track {
            HStack(spacing: DS.Space.s2) {
                ArtworkView(image: nowPlaying.artwork, palette: nowPlaying.palette, cornerRadius: DS.Radius.xs, identity: track.cacheKey)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    nowPlaying.perform(.playPause)
                } label: {
                    Image(systemName: snapshot.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(snapshot.state == .playing ? "Pause" : "Play")
            }
            .padding(DS.Space.s2)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: DS.Radius.sm))
            .contentShape(.rect)
            .onTapGesture { env.section = .nowPlaying }
        }
    }
}
