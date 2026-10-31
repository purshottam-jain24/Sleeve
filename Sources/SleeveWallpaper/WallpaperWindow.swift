import AppKit
import AVFoundation

/// Borderless, click-through window at desktop level showing the video.
final class WallpaperWindow: NSWindow {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        ignoresMouseEvents = true

        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(playerLayer)
        contentView = view
    }

    func place(on screen: NSScreen) {
        setFrame(screen.frame, display: true)
        playerLayer.frame = contentView?.bounds ?? .zero
        playerLayer.contentsScale = screen.backingScaleFactor
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
