#if DEBUG
import SleeveCore
import AppKit
import SwiftUI

/// Debug-only: when `SLEEVE_SNAPSHOT_DIR` is set, visits every section and saves a
/// PNG of the main window. Lets UI be reviewed without Screen Recording permission.
@MainActor
enum SnapshotTour {
    static func runIfRequested(_ env: AppEnvironment) {
        guard let dir = ProcessInfo.processInfo.environment["SLEEVE_SNAPSHOT_DIR"] else { return }
        if let art = ProcessInfo.processInfo.environment["SLEEVE_DEMO_ARTWORK"] {
            if ProcessInfo.processInfo.environment["SLEEVE_DEMO_SECTIONS"] == "1" {
                designTour(env, dir: dir, artworkPaths: art.components(separatedBy: ","))
            } else {
                layoutMatrix(env, dir: dir, artworkPaths: art.components(separatedBy: ","))
            }
            return
        }
        if ProcessInfo.processInfo.environment["SLEEVE_SNAPSHOT_FULLSCREEN"] == "1" {
            fullScreenCheck(dir: dir)
            return
        }
        // A locked screen puts the app into App Nap, which stretches the sleeps below.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Snapshot tour")
        Task {
            defer { ProcessInfo.processInfo.endActivity(activity) }
            try? await Task.sleep(for: .seconds(2))
            for section in AppSection.allCases {
                env.section = section
                // Show long screens in full by making the window very tall.
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
                    let height: CGFloat = section == .glow ? 2700 : 800
                    window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - height, width: 1240, height: height), display: true)
                }
                try? await Task.sleep(for: .seconds(2.5))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
                      let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("ui-\(section.rawValue).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                // cacheDisplay skips layer-hosted content (the glow previews), so also
                // render the Core Animation tree.
                if let layer = view.layer {
                    let scale = window.backingScaleFactor
                    let size = view.bounds.size
                    if let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                           bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        ctx.scaleBy(x: scale, y: scale)
                        layer.presentation()?.render(in: ctx) ?? layer.render(in: ctx)
                        if let image = ctx.makeImage() {
                            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("layers-\(section.rawValue).png"))
                        }
                    }
                }
            }
            env.section = .nowPlaying
        }
    }
}
extension SnapshotTour {
    /// Captures Now Playing and Lyrics with a demo track at several window sizes, with and
    /// without the sidebar, with and without lyrics, for each artwork shape.
    static func layoutMatrix(_ env: AppEnvironment, dir: String, artworkPaths: [String]) {
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Layout snapshots")
        let lrc = (0..<40).map { String(format: "[%02d:%02d.00]", ($0 * 4) / 60, ($0 * 4) % 60) + ["Bas mil jaye, kehni ae", "Neon on the water, we were young", "Every light in the city knows your name", "Hold the line until the morning"][$0 % 4] }.joined(separator: "\n")
        let document = LyricsDocument(synced: LRCParser.parse(lrc), plain: [], sourceName: "Demo")
        Task {
            defer { ProcessInfo.processInfo.endActivity(activity) }
            try? await Task.sleep(for: .seconds(2))
            for (index, path) in artworkPaths.enumerated() {
                guard let image = NSImage(contentsOfFile: path) else { continue }
                let track = Track(title: index == 0 ? "The Beast (Official Audio) Cheema Y | Gur Sidhu | Punjabi Song 2024" : "Midnight Drive",
                                  artist: index == 0 ? "Brown Town Music" : "Sleeve Demo", album: index == 0 ? "" : "Night Lines",
                                  duration: 200, identifier: "demo:\(index)")
                env.nowPlaying.debugShow(PlaybackSnapshot(source: .spotify, state: .playing, track: track, position: 30, volume: 0.6,
                                                          playerName: "Spotify", playerBundleIdentifier: "com.spotify.client"), artwork: image)
                env.settings.settings.lyrics.isEnabled = true
                for lyrics in [false, true] {
                    for sidebar in [true, false] {
                        for size in [NSSize(width: 1240, height: 800), NSSize(width: 900, height: 640), NSSize(width: 1680, height: 1000)] {
                            env.section = .nowPlaying
                            try? await Task.sleep(for: .milliseconds(300))
                            env.lyrics.debugShow(lyrics ? .loaded(document) : .notFound)
                            env.columnVisibility = sidebar ? .all : .detailOnly
                            guard let window = mainWindow else { continue }
                            window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
                            try? await Task.sleep(for: .seconds(1.2))
                            capture(window, to: "\(dir)/np-art\(index)-\(lyrics ? "lyrics" : "nolyrics")-\(sidebar ? "sidebar" : "full")-\(Int(size.width)).png")
                        }
                    }
                }
                env.section = .lyrics
                env.lyrics.debugShow(.failed("Demo"))
                env.columnVisibility = .all
                try? await Task.sleep(for: .seconds(1.2))
                if let window = mainWindow { capture(window, to: "\(dir)/lyrics-art\(index).png") }
            }
            NSApp.terminate(nil)
        }
    }

    /// Every screen once with a demo track (first artwork), plus Now Playing with and
    /// without lyrics for each artwork, and the menu bar panel's main states.
    static func designTour(_ env: AppEnvironment, dir: String, artworkPaths: [String]) {
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Design snapshots")
        let lines = ["Neon on the water, we were young", "Every light in the city knows your name", "Hold the line until the morning",
                     "Bas mil jaye, kehni ae", "Slow dance in the parking lot", "Say it like you mean it this time"]
        var lrc: [String] = []
        for i in 0..<48 {
            let seconds: Int = i * 4
            lrc.append(String(format: "[%02d:%02d.00]", seconds / 60, seconds % 60) + lines[i % lines.count])
        }
        let document = LyricsDocument(synced: LRCParser.parse(lrc.joined(separator: "\n")), plain: [], sourceName: "LRCLIB")
        func show(_ index: Int) {
            guard let image = NSImage(contentsOfFile: artworkPaths[index]) else { return }
            let track = index == 0
                ? Track(title: "Midnight Drive", artist: "Aria Sol", album: "Low Light", duration: 214, identifier: "demo:0")
                : Track(title: "The Beast", artist: "Cheema Y", album: "", duration: 188, identifier: "demo:1")
            env.nowPlaying.debugShow(PlaybackSnapshot(source: .spotify, state: .playing, track: track, position: 30, volume: 0.6,
                                                      playerName: "Spotify", playerBundleIdentifier: "com.spotify.client"), artwork: image)
        }
        Task {
            defer { ProcessInfo.processInfo.endActivity(activity) }
            try? await Task.sleep(for: .seconds(2))
            env.settings.settings.lyrics.isEnabled = true
            env.columnVisibility = .all
            show(0)
            let heights: [AppSection: CGFloat] = [.glow: 2900, .wallpaper: 1100, .sources: 1000, .settings: 1300]
            for section in AppSection.allCases {
                env.section = section
                env.lyrics.debugShow(.loaded(document))
                guard let window = mainWindow else { continue }
                window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1240, height: heights[section] ?? 800)), display: true)
                try? await Task.sleep(for: .seconds(1.8))
                capture(window, to: "\(dir)/\(section.rawValue).png")
                // Long screens: scroll down and capture the rest.
                if section == .glow, let scroll = window.contentView.flatMap(findScrollView), let document = scroll.documentView {
                    for (page, y) in [(2, 720.0), (3, 1440.0)] {
                        let top = document.isFlipped ? y : document.bounds.height - scroll.contentView.bounds.height - y
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, top)))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        try? await Task.sleep(for: .seconds(1.5))
                        capture(window, to: "\(dir)/\(section.rawValue)-\(page).png")
                    }
                }
            }
            // Narrow window: cards fall back to one column.
            if let window = mainWindow {
                env.section = .settings
                window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 860, height: 1500)), display: true)
                try? await Task.sleep(for: .seconds(1.5))
                capture(window, to: "\(dir)/settings-narrow.png")
            }
            // The menu bar panel, hosted in a plain window.
            let host = NSHostingView(rootView: MenuBarPanel().environment(env))
            let panel = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.backgroundColor = NSColor(white: 0.13, alpha: 1)
            panel.contentView = host
            panel.setContentSize(host.fittingSize)
            panel.orderFront(nil)
            try? await Task.sleep(for: .seconds(1.5))
            capture(panel, to: "\(dir)/menubar.png")
            panel.orderOut(nil)

            for index in artworkPaths.indices {
                show(index)
                for (name, state) in [("lyrics", LyricsService.State.loaded(document)), ("nolyrics", .notFound)] {
                    env.section = .nowPlaying
                    env.lyrics.debugShow(state)
                    guard let window = mainWindow else { continue }
                    window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1240, height: 800)), display: true)
                    try? await Task.sleep(for: .seconds(1.5))
                    capture(window, to: "\(dir)/np-\(index)-\(name).png")
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })
    }

    private static func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews { if let found = findScrollView(child) { return found } }
        return nil
    }

    private static func capture(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Enters full screen, records what chrome is visible, saves a capture, then quits.
    static func fullScreenCheck(dir: String) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) else { return }
            window.toggleFullScreen(nil)
            try? await Task.sleep(for: .seconds(3))
            let options = NSApp.presentationOptions
            var report = "fullScreen=\(window.styleMask.contains(.fullScreen))\n"
            report += "toolbarVisible=\(window.toolbar?.isVisible ?? false)\n"
            report += "autoHideMenuBar=\(options.contains(.autoHideMenuBar)) autoHideDock=\(options.contains(.autoHideDock)) autoHideToolbar=\(options.contains(.autoHideToolbar))\n"
            report += "contentTopInset=\(window.contentLayoutRect.maxY == window.contentView?.bounds.maxY ? 0 : (window.contentView?.bounds.maxY ?? 0) - window.contentLayoutRect.maxY)\n"
            try? report.write(toFile: dir + "/fullscreen.txt", atomically: true, encoding: .utf8)
            if let view = window.contentView?.superview ?? window.contentView, let layer = view.layer {
                let scale = window.backingScaleFactor
                if let ctx = CGContext(data: nil, width: Int(view.bounds.width * scale), height: Int(view.bounds.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.scaleBy(x: scale, y: scale)
                    layer.render(in: ctx)
                    if let image = ctx.makeImage() {
                        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                            .write(to: URL(fileURLWithPath: dir + "/fullscreen.png"))
                    }
                }
            }
            window.toggleFullScreen(nil)
            try? await Task.sleep(for: .seconds(1.5))
            NSApp.terminate(nil)
        }
    }
}
#endif
