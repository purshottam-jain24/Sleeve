import AppKit
import Observation

/// Live video wallpaper plus the "artwork on the lock screen" desktop picture.
///
/// Nothing runs on its own: the video plays only after the user picks one, and the
/// artwork picture is shown only while that switch is on and music is playing. The
/// system desktop picture shows, in order of preference: the song's artwork, a still of
/// the wallpaper video, or the user's own picture (restored exactly, also after a crash).
@MainActor
@Observable
public final class WallpaperController {
    public let library: WallpaperLibrary
    public private(set) var activeVideo: WallpaperVideo?
    public private(set) var screenSaverInstalled = ScreenSaverInstaller.isInstalled || ScreenSaverInstaller.hasLegacy
    public private(set) var isShowingArtwork = false
    public var errorMessage: String?
    /// The user paused the video (it stays on screen as a still).
    public var isPaused = false {
        didSet { player.isUserPaused = isPaused }
    }
    /// Called when the active video changes so the app can persist it.
    @ObservationIgnored public var onActiveVideoChange: ((UUID?) -> Void)?

    @ObservationIgnored private let player = WallpaperPlayer()
    @ObservationIgnored private let desktop: DesktopPicture
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var artworkImage: URL?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let saverCard: ScreenSaverNowPlayingWriter
    @ObservationIgnored private var cardClearTask: Task<Void, Never>?

    public init(root: URL = WallpaperLibrary.defaultRoot) {
        library = WallpaperLibrary(root: root)
        desktop = DesktopPicture(directory: root.appendingPathComponent("SystemWallpaper", isDirectory: true))
        ScreenSaverInstaller.root = root
        saverCard = ScreenSaverNowPlayingWriter(directory: root.appendingPathComponent("NowPlaying", isDirectory: true))
        saverCard.clear()
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktop.screensChanged() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktop.spaceChanged() }
        }
    }

    // MARK: Lifecycle

    /// Resumes the saved video, or puts back the user's picture if a previous run
    /// didn't get to (crash, force quit).
    public func start(activeVideoID: UUID?) {
        guard !started else { return }
        started = true
        desktop.repairLegacyOriginals()
        library.importLegacyLibrary()
        Task { await library.preparePreviews() }
        Task.detached(priority: .utility) {
            ScreenSaverInstaller.migrateLegacy()
            ScreenSaverInstaller.refreshIfInstalled()
        }
        if let video = library.video(withID: activeVideoID) {
            play(video)
        } else if desktop.hasSavedOriginal {
            desktop.restore()
        }
    }

    /// Puts the user's own desktop picture back. Call when quitting.
    public func prepareForQuit() {
        saverCard.clear()
        desktop.restore()
    }

    public func configure(allDisplays: Bool, pauseOnBattery: Bool) {
        if player.showOnAllDisplays != allDisplays { player.showOnAllDisplays = allDisplays }
        if player.pausesOnBattery != pauseOnBattery { player.pausesOnBattery = pauseOnBattery }
    }

    // MARK: Video wallpaper

    public func play(_ video: WallpaperVideo) {
        activeVideo = video
        isPaused = false
        let url = library.videoURL(for: video)
        player.play(url: url)
        onActiveVideoChange?(video.id)
        updateDesktopPicture()
        Task { await ScreenSaverInstaller.sync(video: url) }
    }

    /// Turns live wallpaper off and puts the user's picture back.
    public func stopVideo() {
        guard activeVideo != nil else { return }
        player.stop()
        activeVideo = nil
        onActiveVideoChange?(nil)
        updateDesktopPicture()
        Task { await ScreenSaverInstaller.sync(video: nil) }
    }

    public func importVideos(_ urls: [URL]) async {
        for url in urls {
            do {
                let video = try await library.importVideo(from: url)
                if activeVideo == nil { play(video) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func delete(_ video: WallpaperVideo) {
        if video.id == activeVideo?.id { stopVideo() }
        library.delete(video)
    }

    public func setScreenSaverInstalled(_ enabled: Bool) {
        screenSaverInstalled = enabled
        let video = activeVideo.map(library.videoURL(for:))
        Task {
            let error: String? = await Task.detached(priority: .userInitiated) {
                if enabled {
                    do { try ScreenSaverInstaller.install() } catch { return error.localizedDescription }
                } else {
                    ScreenSaverInstaller.remove()
                }
                return nil
            }.value
            if enabled, error == nil { await ScreenSaverInstaller.sync(video: video) }
            screenSaverInstalled = ScreenSaverInstaller.isInstalled
            if let error { errorMessage = "Couldn’t install the screensaver: \(error)" }
        }
    }

    // MARK: Artwork on the lock screen

    /// Shows the artwork as the desktop picture (and so on the lock screen). Rendering
    /// happens once per track, off the main thread.
    public func showArtwork(_ artwork: NSImage, key: String) {
        hideTask?.cancel()
        hideTask = nil
        guard key != artworkKey else { return }
        artworkKey = key
        guard let cg = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let pixels = (screen?.frame.size ?? CGSize(width: 2560, height: 1600))
            .applying(CGAffineTransform(scaleX: screen?.backingScaleFactor ?? 2, y: screen?.backingScaleFactor ?? 2))
        let directory = desktop.imagesDirectory
        artworkTask?.cancel()
        artworkTask = Task {
            let rendered = await Task.detached(priority: .utility) {
                try? ArtworkWallpaper.render(cg, pixelSize: pixels, into: directory)
            }.value
            guard !Task.isCancelled, artworkKey == key, let rendered else { return }
            artworkImage = rendered
            isShowingArtwork = true
            updateDesktopPicture()
        }
    }

    // MARK: Screensaver

    /// Keeps the Sleeve screensaver's song details current. Only written while that
    /// screensaver is installed; cleared 20 s after music stops, so the screensaver goes
    /// back to the wallpaper video.
    public func nowPlayingChanged(_ card: NowPlayingCard?, artwork: NSImage?, artworkKey key: String?) {
        guard screenSaverInstalled, let card else {
            scheduleCardClear(after: screenSaverInstalled ? .seconds(20) : .zero)
            return
        }
        saverCard.write(card, artwork: artwork, artworkKey: key)
        if card.isPlaying {
            cardClearTask?.cancel()
            cardClearTask = nil
        } else {
            scheduleCardClear(after: .seconds(20))
        }
    }

    private func scheduleCardClear(after delay: Duration) {
        if delay == .zero {
            cardClearTask?.cancel()
            cardClearTask = nil
            saverCard.clear()
            return
        }
        guard cardClearTask == nil else { return }
        cardClearTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            cardClearTask = nil
            saverCard.clear()
        }
    }

    /// Stops showing artwork after `delay`, so a short pause or the gap between songs
    /// doesn't flash the desktop.
    public func hideArtwork(after delay: Duration = .seconds(20)) {
        guard artworkKey != nil else { return }
        if delay == .zero {
            hideTask?.cancel()
        } else if hideTask != nil {
            return
        }
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hideTask = nil
            artworkTask?.cancel()
            artworkKey = nil
            artworkImage = nil
            isShowingArtwork = false
            updateDesktopPicture()
        }
    }

    private func updateDesktopPicture() {
        player.isHiddenForArtwork = artworkImage != nil
        if let artworkImage {
            desktop.show(artworkImage)
        } else if let activeVideo {
            let url = library.videoURL(for: activeVideo)
            Task { await desktop.mirror(url) }
        } else if desktop.hasSavedOriginal {
            desktop.restore()
        }
    }
}
