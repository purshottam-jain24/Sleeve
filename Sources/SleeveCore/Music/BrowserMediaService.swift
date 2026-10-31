import AppKit
import Foundation
import ImageIO

/// Now playing for media in web browsers (YouTube, YouTube Music, SoundCloud, …).
///
/// Two tiers:
/// - **Basic** (Automation permission only): finds media tabs from their URL and title.
///   YouTube artwork comes from the video ID; play state from whether the browser is
///   producing sound (Core Audio process objects).
/// - **Full** (the browser's "Allow JavaScript from Apple Events" is on): reads the page's
///   Media Session metadata (title, artist, artwork for any site), position and duration,
///   and enables play/pause, next, previous, seek and volume.
///
/// Browsers are only queried while one is producing sound, or briefly afterwards to
/// notice a pause, so this costs nothing while nothing plays in a browser.
@MainActor
public final class BrowserMediaService: MusicProvider {
    public let source: MusicSourceID = .web
    public private(set) var status: ProviderStatus = .notRunning
    public private(set) var snapshot: PlaybackSnapshot?
    public var onChange: (@MainActor () -> Void)?

    /// Browsers where page scripting is off (basic tier only), keyed by bundle ID.
    public private(set) var javaScriptOff: Set<String> = []

    private struct TabRef: Equatable {
        var browser: Browser
        var window: Int
        var tab: Int
        var url: URL
    }

    private let runner = AppleScriptRunner.shared
    private var pollTask: Task<Void, Never>?
    private var automationDenied: Set<String> = []
    private var current: TabRef?
    private var lastAudibleAt: Date = .distantPast

    public init() {}

    public var installedBrowsers: [Browser] {
        Browser.all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    private var runningBrowsers: [Browser] {
        Browser.all.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }

    // MARK: Lifecycle

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = await self?.poll() ?? 3
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        apply(snapshot: nil, status: .notRunning)
    }

    public func refresh() async {
        _ = await poll()
    }

    public func retryPermissions() async {
        automationDenied.removeAll()
        javaScriptOff.removeAll()
        await refresh()
    }

    /// One detection pass. Returns seconds until the next pass.
    private func poll() async -> Double {
        let running = runningBrowsers
        guard !running.isEmpty else {
            current = nil
            apply(snapshot: nil, status: installedBrowsers.isEmpty ? .notInstalled : .notRunning)
            return 4
        }
        let outputs = AudioProcessMonitor.bundleIDsWithActiveOutput()
        let audible = running.filter { $0.isPlayingAudio(activeOutputs: outputs) }
        if !audible.isEmpty { lastAudibleAt = Date() }

        // Silent browsers: keep watching a known tab (to show it paused) but never start
        // querying browsers that aren't making sound.
        let candidates: [Browser]
        if !audible.isEmpty {
            candidates = audible
        } else if let current, running.contains(current.browser), Date().timeIntervalSince(lastAudibleAt) < 600 {
            candidates = [current.browser]
        } else {
            current = nil
            apply(snapshot: nil, status: .connected)
            return 2.5
        }

        var best: (TabRef, PlaybackSnapshot)?
        for browser in candidates where !automationDenied.contains(browser.bundleID) {
            if let found = await detect(in: browser, isAudible: audible.contains(browser)) {
                if best == nil || (found.1.state == .playing && best!.1.state != .playing) { best = found }
            }
        }
        current = best?.0
        let deniedCurrent = candidates.allSatisfy { automationDenied.contains($0.bundleID) }
        let newStatus: ProviderStatus = deniedCurrent ? .limited(.automationDenied)
            : (best.map { javaScriptOff.contains($0.0.browser.bundleID) } == true
                ? .limited(.browserScriptingOff(best!.0.browser.name)) : .connected)
        apply(snapshot: best?.1, status: newStatus)
        return audible.isEmpty ? 4 : 2
    }

    // MARK: Detection

    private func detect(in browser: Browser, isAudible: Bool) async -> (TabRef, PlaybackSnapshot)? {
        let tabs: [TabRef]
        let activeIndices: [Int]
        do {
            (tabs, activeIndices) = try await listTabs(browser)
        } catch {
            if error == .automationDenied { automationDenied.insert(browser.bundleID) }
            return nil
        }
        let media = tabs.filter { WebMediaSite.site(for: $0.url) != nil }
        guard !media.isEmpty else { return nil }

        // Full tier: ask each media tab (at most a few) what it's doing.
        if !javaScriptOff.contains(browser.bundleID) {
            var paused: (TabRef, PlaybackSnapshot)?
            for tab in media.prefix(6) {
                switch await readPage(tab) {
                case .success(let info?):
                    guard info.hasMedia == true else { continue }
                    let snapshot = makeSnapshot(tab: tab, info: info, title: nil, playing: info.paused == false)
                    if snapshot.state == .playing { return (tab, snapshot) }
                    if paused == nil || tab.url == current?.url { paused = (tab, snapshot) }
                case .success(nil):
                    continue
                case .failure(let error):
                    if case .scriptFailed(_, let message) = error, message.localizedCaseInsensitiveContains("javascript") {
                        javaScriptOff.insert(browser.bundleID)
                    } else if error == .automationDenied {
                        automationDenied.insert(browser.bundleID)
                        return nil
                    }
                }
                if javaScriptOff.contains(browser.bundleID) { break }
            }
            if !javaScriptOff.contains(browser.bundleID) { return paused }
        }

        // Basic tier: YouTube only (artwork is derivable from the URL). Prefer the tab we
        // were already showing, then the front window's active tab, then the first one.
        let youtube = media.filter { WebMediaSite.site(for: $0.url) == .youtube || WebMediaSite.site(for: $0.url) == .youtubeMusic }
        let chosen = youtube.first { $0.url == current?.url }
            ?? youtube.first { tab in activeIndices.indices.contains(tab.window - 1) && activeIndices[tab.window - 1] == tab.tab && tab.window == 1 }
            ?? youtube.first
        guard let chosen else { return nil }
        let title = tabTitles[chosen.url] ?? ""
        var snapshot = makeSnapshot(tab: chosen, info: nil, title: title, playing: isAudible)
        // Tab titles rarely name the artist; the channel does (needed for lyrics).
        if snapshot.track?.artist.isEmpty == true, let id = WebMediaSite.youtubeVideoID(from: chosen.url),
           let channel = await youtubeChannel(videoID: id) {
            snapshot.track?.artist = WebMediaSite.artist(fromChannel: channel)
        }
        return (chosen, snapshot)
    }

    private var tabTitles: [URL: String] = [:]
    /// Channel names by video ID; "" when the lookup failed (not retried).
    private var channels: [String: String] = [:]

    private func youtubeChannel(videoID: String) async -> String? {
        if let cached = channels[videoID] { return cached.isEmpty ? nil : cached }
        struct OEmbed: Decodable { var author_name: String? }
        var name = ""
        if let url = WebMediaSite.youtubeOEmbedURL(videoID: videoID),
           let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 6)),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let author = try? JSONDecoder().decode(OEmbed.self, from: data).author_name {
            name = author
        }
        if channels.count > 200 { channels.removeAll() }
        channels[videoID] = name
        return name.isEmpty ? nil : name
    }

    private func listTabs(_ browser: Browser) async throws(MusicSourceError) -> ([TabRef], [Int]) {
        let source: String
        switch browser.kind {
        case .safari:
            source = """
            tell application id "\(browser.bundleID)"
                return {URL of every tab of every window, name of every tab of every window, index of current tab of every window}
            end tell
            """
        case .chromium:
            source = """
            tell application id "\(browser.bundleID)"
                return {URL of every tab of every window, title of every tab of every window, active tab index of every window}
            end tell
            """
        }
        let result = try await runner.run(source) { d -> ([[String]], [[String]], [Int]) in
            func strings(_ list: NSAppleEventDescriptor?) -> [[String]] {
                guard let list else { return [] }
                return (1...max(list.numberOfItems, 1)).compactMap { w in
                    guard let window = list.item(w) else { return nil }
                    return (1...max(window.numberOfItems, 1)).map { window.item($0)?.stringValue ?? "" }
                }
            }
            let actives = d.item(3).map { list in (1...max(list.numberOfItems, 1)).map { Int(list.item($0)?.int32Value ?? 0) } } ?? []
            return (strings(d.item(1)), strings(d.item(2)), actives)
        }
        var tabs: [TabRef] = []
        for (w, urls) in result.0.enumerated() {
            let titles = result.1.indices.contains(w) ? result.1[w] : []
            for (t, string) in urls.enumerated() {
                guard let url = URL(string: string), url.scheme?.hasPrefix("http") == true else { continue }
                tabs.append(TabRef(browser: browser, window: w + 1, tab: t + 1, url: url))
                tabTitles[url] = titles.indices.contains(t) ? titles[t] : ""
            }
        }
        return (tabs, result.2)
    }

    private func readPage(_ tab: TabRef) async -> Result<PageMediaInfo?, MusicSourceError> {
        do {
            let json = try await runJavaScript(WebMediaScripts.readMedia, in: tab)
            guard let data = json?.data(using: .utf8) else { return .success(nil) }
            return .success(try? JSONDecoder().decode(PageMediaInfo.self, from: data))
        } catch {
            return .failure(error)
        }
    }

    private func runJavaScript(_ js: String, in tab: TabRef) async throws(MusicSourceError) -> String? {
        let literal = WebMediaScripts.appleScriptLiteral(js)
        let source: String
        switch tab.browser.kind {
        case .safari:
            source = """
            tell application id "\(tab.browser.bundleID)" to do JavaScript "\(literal)" in tab \(tab.tab) of window \(tab.window)
            """
        case .chromium:
            source = """
            tell application id "\(tab.browser.bundleID)" to execute tab \(tab.tab) of window \(tab.window) javascript "\(literal)"
            """
        }
        // Parameterised by tab position, so don't keep compiled copies around.
        return try await runner.run(source, cache: false) { $0.stringValue }
    }

    /// When the page read the position; falls back to now if the page clock looks off.
    static func readDate(_ info: PageMediaInfo?) -> Date {
        let now = Date()
        guard let ms = info?.now else { return now }
        let read = Date(timeIntervalSince1970: ms / 1000)
        return abs(read.timeIntervalSince(now)) < 3 ? min(read, now) : now
    }

    private func makeSnapshot(tab: TabRef, info: PageMediaInfo?, title: String?, playing: Bool) -> PlaybackSnapshot {
        let site = WebMediaSite.site(for: tab.url) ?? .youtube
        let videoID = WebMediaSite.youtubeVideoID(from: tab.url)
        let parsed = WebMediaSite.parseTitle(info?.title ?? title ?? "", site: site)
        // A singer named in the video title beats the channel, which is often a label.
        let channel = info?.artist.flatMap { $0.isEmpty ? nil : WebMediaSite.artist(fromChannel: $0) }
        let artist = parsed.artist.isEmpty ? channel ?? "" : parsed.artist
        // YouTube's Media Session artwork is a letterboxed thumbnail; the video ID gives a
        // clean 16:9 one. YouTube Music's Media Session artwork is proper square art.
        let artworkURL: URL? = site == .youtube
            ? videoID.flatMap { WebMediaSite.youtubeThumbnailURLs(videoID: $0).first }
            : info?.artwork.flatMap(URL.init(string:))
        let track = Track(
            title: parsed.title.isEmpty ? tab.url.host ?? "Web" : parsed.title,
            artist: artist,
            album: info?.album ?? "",
            duration: info?.duration.flatMap { $0 > 0 ? $0 : nil },
            identifier: videoID.map { "yt:\($0)" } ?? tab.url.absoluteString,
            artworkURL: artworkURL
        )
        return PlaybackSnapshot(
            source: .web,
            state: playing ? .playing : .paused,
            track: track,
            position: info?.time,
            positionTimestamp: Self.readDate(info),
            volume: info?.volume,
            isEnriched: true,
            playerName: tab.browser.name,
            playerBundleIdentifier: tab.browser.bundleID,
            supportsControl: info != nil
        )
    }

    // MARK: Commands

    public func perform(_ command: PlaybackCommand) async throws(MusicSourceError) {
        guard let tab = current else { throw .notRunning }
        if javaScriptOff.contains(tab.browser.bundleID) { throw .browserScriptingOff(tab.browser.name) }
        let js: String = switch command {
        case .playPause: WebMediaScripts.playPause
        case .next: WebMediaScripts.next
        case .previous: WebMediaScripts.previous
        case .seek(let seconds): WebMediaScripts.seek(seconds)
        case .setVolume(let value): WebMediaScripts.volume(value)
        }
        _ = try await runJavaScript(js, in: tab)
        try? await Task.sleep(for: .milliseconds(250))
        await refresh()
    }

    public func revealPlayer() {
        guard let tab = current else { return }
        let source: String = switch tab.browser.kind {
        case .safari: """
            tell application id "\(tab.browser.bundleID)"
                set current tab of window \(tab.window) to tab \(tab.tab) of window \(tab.window)
                set index of window \(tab.window) to 1
                activate
            end tell
            """
        case .chromium: """
            tell application id "\(tab.browser.bundleID)"
                set active tab index of window \(tab.window) to \(tab.tab)
                set index of window \(tab.window) to 1
                activate
            end tell
            """
        }
        Task { _ = try? await runner.run(source, cache: false) { _ in () } }
    }

    // MARK: Artwork

    public func artworkData(for track: Track) async -> Data? {
        var urls: [URL] = []
        if let id = track.identifier, id.hasPrefix("yt:") {
            urls = WebMediaSite.youtubeThumbnailURLs(videoID: String(id.dropFirst(3)))
        } else if let url = track.artworkURL {
            urls = [url]
        }
        for url in urls where url.scheme == "https" {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let size = Self.pixelSize(of: data), size.width > 120 else { continue }
            // Thumbnails often frame a square cover with flat bars (and hqdefault is 4:3
            // with black bars around 16:9 video); show just the picture.
            if let trimmed = ArtworkTrim.trimmed(data) { return trimmed }
            if url.lastPathComponent == "hqdefault.jpg" { return Self.cropLetterbox(data) ?? data }
            return data
        }
        return nil
    }

    private static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    private static func cropLetterbox(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let height = CGFloat(image.width) * 9 / 16
        let rect = CGRect(x: 0, y: (CGFloat(image.height) - height) / 2, width: CGFloat(image.width), height: height)
        guard let cropped = image.cropping(to: rect.integral) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cropped, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func apply(snapshot newSnapshot: PlaybackSnapshot?, status newStatus: ProviderStatus) {
        // A paused tab re-polled with nothing changed but the timestamp is not a change.
        var newSnapshot = newSnapshot
        if var candidate = newSnapshot, let old = snapshot, candidate.state == .paused, old.state == .paused {
            candidate.positionTimestamp = old.positionTimestamp
            if candidate == old { newSnapshot = old }
        }
        guard newSnapshot != snapshot || newStatus != status else { return }
        snapshot = newSnapshot
        status = newStatus
        onChange?()
    }
}
