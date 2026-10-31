import SleeveCore
import SleeveWallpaper
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Live video wallpaper library and the lock-screen artwork switch.
struct WallpaperScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isDropTargeted = false
    @State private var renaming: WallpaperVideo?
    @State private var newName = ""

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: DS.Space.s4)]

    var body: some View {
        @Bindable var settings = env.settings
        let wallpaper = env.wallpaper
        let library = wallpaper.library

        ZStack {
            AmbientBackdrop(artwork: nil, palette: env.nowPlaying.palette, intensity: 0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    PageHeader(title: "Wallpaper", subtitle: "Your own videos on the desktop, and the song's artwork on the lock screen.") {
                        Button(action: importVideo) { Label("Import Video…", systemImage: "plus") }.buttonStyle(.quiet)
                    }

                    if let active = wallpaper.activeVideo ?? demoActiveVideo(library) {
                        ActiveWallpaperCard(video: active, thumbnail: library.thumbnail(for: active))
                    }

                    MasonryLayout {
                        GlassCard(title: "Lock screen", symbol: "lock",
                                  caption: "macOS adds its own play, skip and timeline controls on the lock screen. Your picture comes back when the music stops or you quit.") {
                            SettingToggle(title: "Show artwork while music plays",
                                          detail: "Uses the song's cover as your desktop and lock screen picture.",
                                          isOn: $settings.settings.wallpaper.artworkOnLockScreen)
                            RowDivider()
                            SettingToggle(title: "Sleeve screensaver",
                                          detail: "The song, its cover and a live timeline while music plays; your wallpaper video otherwise. Turning it off puts your previous screensaver back.",
                                          isOn: Binding(get: { wallpaper.screenSaverInstalled }, set: { wallpaper.setScreenSaverInstalled($0) }))
                        }

                        GlassCard(title: "Playback", symbol: "play.rectangle",
                                  caption: "Videos pause by themselves while the screen is locked or asleep, behind full-screen apps and in Low Power Mode.") {
                            SettingToggle(title: "All displays", detail: "Off: only your main display.", isOn: $settings.settings.wallpaper.allDisplays)
                            RowDivider()
                            SettingToggle(title: "Pause on battery", detail: "Shows a still frame until you plug in.",
                                          isOn: $settings.settings.wallpaper.pauseOnBattery)
                        }
                    }

                    GlassCard(title: "Library", symbol: "film.stack") {
                        if library.videos.isEmpty && library.importingCount == 0 {
                            EmptyLibrary(onImport: importVideo)
                        } else {
                            LazyVGrid(columns: columns, spacing: DS.Space.s5) {
                                ForEach(0..<library.importingCount, id: \.self) { _ in ImportingCard() }
                                ForEach(library.videos) { video in
                                    WallpaperCard(video: video,
                                                  thumbnail: library.thumbnail(for: video),
                                                  previewURL: library.previewURL(for: video),
                                                  isActive: video.id == wallpaper.activeVideo?.id)
                                        .onTapGesture { withAnimation(DS.Motion.smooth) { wallpaper.play(video) } }
                                        .contextMenu {
                                            Button("Set as Wallpaper") { wallpaper.play(video) }
                                            Button("Rename…") {
                                                newName = video.name
                                                renaming = video
                                            }
                                            Button("Show in Finder") {
                                                NSWorkspace.shared.activateFileViewerSelecting([library.videoURL(for: video)])
                                            }
                                            Divider()
                                            Button("Delete", role: .destructive) { wallpaper.delete(video) }
                                        }
                                }
                            }
                        }
                    } accessory: {
                        if !library.videos.isEmpty {
                            Text(library.videos.count == 1 ? "1 video" : "\(library.videos.count) videos")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay { if isDropTargeted { DropHighlight() } }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .alert("Rename Wallpaper", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let renaming { library.rename(renaming, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Something went wrong", isPresented: Binding(get: { wallpaper.errorMessage != nil }, set: { if !$0 { wallpaper.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wallpaper.errorMessage ?? "")
        }
    }

    /// Debug design tours show the banner without touching the real desktop.
    private func demoActiveVideo(_ library: WallpaperLibrary) -> WallpaperVideo? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SLEEVE_DEMO_ACTIVE_WALLPAPER"] != nil { return library.videos.first }
        #endif
        return nil
    }

    private func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = true
        panel.message = "Choose videos to use as wallpaper. They're copied into Sleeve."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await env.wallpaper.importVideos(urls) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) else { return }
                Task { @MainActor in await env.wallpaper.importVideos([url]) }
            }
        }
        return true
    }
}

/// The video on the desktop right now, shown as a full-bleed banner.
private struct ActiveWallpaperCard: View {
    @Environment(AppEnvironment.self) private var env
    var video: WallpaperVideo
    var thumbnail: NSImage?

    var body: some View {
        let wallpaper = env.wallpaper
        ZStack(alignment: .bottomLeading) {
            Thumbnail(image: thumbnail)
            // Scrims for legible text over any frame: darker toward the bottom-left.
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .leading, endPoint: .center)

            HStack(alignment: .bottom, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(wallpaper.isPaused ? Color.white.opacity(0.5) : DS.Palette.accent)
                            .frame(width: 6, height: 6)
                        Text(wallpaper.isPaused ? "PAUSED" : "ON YOUR DESKTOP")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text(video.name)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(formatDuration(video.duration) + " loop")
                        .font(DS.Font.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: DS.Space.s4)
                HStack(spacing: DS.Space.s2) {
                    Button { wallpaper.isPaused.toggle() } label: {
                        Label(wallpaper.isPaused ? "Resume" : "Pause", systemImage: wallpaper.isPaused ? "play.fill" : "pause.fill")
                    }
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: DS.Radius.sm, style: .continuous))
                    Button { withAnimation(DS.Motion.smooth) { wallpaper.stopVideo() } } label: {
                        Label("Turn Off", systemImage: "power")
                    }
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: DS.Radius.sm, style: .continuous))
                    .help("Stops the video and puts your own desktop picture back")
                }
                .buttonStyle(.quiet)
            }
            .padding(DS.Space.s6)
        }
        .frame(height: 240)
        .clipShape(.rect(cornerRadius: DS.Radius.card, style: .continuous))
        .cardSurface()
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct WallpaperCard: View {
    var video: WallpaperVideo
    var thumbnail: NSImage?
    var previewURL: URL?
    var isActive: Bool

    @State private var isHovering = false
    @State private var showsPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { Thumbnail(image: thumbnail) }
                .overlay {
                    if showsPreview, let previewURL {
                        LoopingPlayerView(url: previewURL).transition(.opacity)
                    }
                }
                .clipShape(.rect(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(isActive ? DS.Palette.accent.opacity(0.9) : Color.white.opacity(isHovering ? 0.18 : 0.08),
                                      lineWidth: isActive ? 1.5 : 0.5)
                }
                .shadow(color: .black.opacity(isHovering ? 0.4 : 0.25), radius: isHovering ? 14 : 8, y: isHovering ? 8 : 4)

            HStack {
                Text(video.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(formatDuration(video.duration))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, 2)
        }
        .offset(y: isHovering ? -2 : 0)
        .animation(DS.Motion.snappy, value: isHovering)
        .animation(.easeOut(duration: 0.25), value: showsPreview)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .task(id: isHovering) {
            // A short delay so sweeping the pointer across the grid doesn't start videos.
            guard isHovering, previewURL != nil else {
                showsPreview = false
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { showsPreview = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ImportingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Palette.surface)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { ProgressView().controlSize(.small) }
            Text("Importing…").font(.system(size: 12)).foregroundStyle(DS.Palette.textTertiary)
        }
    }
}

private struct EmptyLibrary: View {
    var onImport: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.Palette.textTertiary)
            Text("Drop a video here")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text("MP4 or MOV. Videos are copied into Sleeve, so you can delete the originals.")
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textTertiary)
            Button("Import Video…", action: onImport).buttonStyle(.quiet).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .foregroundStyle(DS.Palette.hairline.opacity(2))
        }
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Palette.accent, lineWidth: 2)
            .background(DS.Palette.accent.opacity(0.06), in: .rect(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay {
                Text("Drop to add to your library")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding(10)
            .allowsHitTesting(false)
    }
}

private struct Thumbnail: View {
    var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(DS.Palette.surface)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film").font(.system(size: 22)).foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .clipped()
    }
}

/// Muted looping preview for a hovered card; torn down as soon as the hover ends.
private struct LoopingPlayerView: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> PlayerNSView { PlayerNSView(url: url) }
    func updateNSView(_ nsView: PlayerNSView, context: Context) {}
    static func dismantleNSView(_ nsView: PlayerNSView, coordinator: ()) { nsView.stop() }

    final class PlayerNSView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?

        init(url: URL) {
            super.init(frame: .zero)
            wantsLayer = true
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer?.addSublayer(playerLayer)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            layer?.sublayers?.first?.frame = bounds
        }

        func stop() {
            player.pause()
            looper?.disableLooping()
            player.removeAllItems()
        }
    }
}

private func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "--:--" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
