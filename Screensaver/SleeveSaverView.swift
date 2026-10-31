import AVFoundation
import CoreImage
import ScreenSaver

/// "Sleeve" screensaver.
///
/// While music plays (and the app's "Show artwork while music plays" switch is on) it
/// shows the song: the cover over a blurred backdrop, title, artist and a live timeline.
/// Otherwise it plays the current wallpaper video, muted and looping. The app shares both
/// through files in ~/Library/Application Support/Sleeve/Wallpaper/, because the
/// screensaver runs in its own macOS process.
@objc(SleeveSaverView)
final class SleeveSaverView: ScreenSaverView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    private let nowPlaying = NowPlayingScene()
    private var card: Card?
    private var cardModified: Date?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // Only the time labels and the card file are polled here; the progress bar, the
        // backdrop and the equaliser are Core Animation animations run by the system.
        animationTimeInterval = 0.25

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)

        nowPlaying.frame = bounds
        nowPlaying.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        nowPlaying.isHidden = true
        layer?.addSublayer(nowPlaying)

        refresh()

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenSaverWillStop), name: .init("com.apple.screensaver.willstop"), object: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func startAnimation() {
        super.startAnimation()
        refresh()
        nowPlaying.startMotion()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player.pause()
        nowPlaying.stopMotion()
    }

    override func animateOneFrame() {
        refresh()
    }

    @objc private func screenSaverWillStop() {
        player.pause()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        nowPlaying.scale = window?.backingScaleFactor ?? 2
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
        guard looper == nil, card == nil else { return }

        let message = "Open Sleeve and choose a wallpaper video."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isPreview ? 11 : 24, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = message.size(withAttributes: attributes)
        message.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    // MARK: State

    private func refresh() {
        loadCard()
        if let card {
            if player.rate != 0 { player.pause() }
            playerLayer.isHidden = true
            nowPlaying.isHidden = false
            nowPlaying.update(card: card, directory: Self.cardDirectory(), now: Date())
        } else {
            nowPlaying.isHidden = true
            playerLayer.isHidden = false
            loadVideo()
            if isAnimating, looper != nil, player.rate == 0 { player.play() }
        }
    }

    /// Re-reads the card only when the file changed (a stat per tick).
    private func loadCard() {
        guard let directory = Self.cardDirectory() else { card = nil; return }
        let url = directory.appendingPathComponent("card.json")
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let modified else {
            if card != nil { card = nil; needsDisplay = true }
            cardModified = nil
            return
        }
        if modified != cardModified {
            cardModified = modified
            card = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Card.self, from: $0) }
            needsDisplay = true
        }
        // A card left behind by a crashed app: playing far past the end of the song.
        if let card, card.isPlaying, let duration = card.duration, let position = card.position(at: Date()),
           position > duration + 30 {
            self.card = nil
        }
    }

    private func loadVideo() {
        let url = Self.videoURL()
        guard url != currentURL else { return }
        currentURL = url
        looper?.disableLooping()
        player.removeAllItems()
        looper = url.map { AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: AVURLAsset(url: $0))) }
        needsDisplay = true
    }

    private static func appDirectory() -> URL? {
        if let override = ProcessInfo.processInfo.environment["SLEEVE_SAVER_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        // The real home folder, not the screensaver host's container.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Application Support/Sleeve/Wallpaper", isDirectory: true)
    }

    private static func cardDirectory() -> URL? {
        appDirectory()?.appendingPathComponent("NowPlaying", isDirectory: true)
    }

    private static func videoURL() -> URL? {
        guard let pointer = appDirectory()?.appendingPathComponent("screensaver-video.txt"),
              let path = try? String(contentsOf: pointer, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Mirrors the app's `NowPlayingCard`.
private struct Card: Decodable, Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double?
    var position: Double?
    var positionDate: Date
    var isPlaying: Bool
    var playerName: String?
    var artworkFile: String?

    func position(at date: Date) -> Double? {
        guard let position else { return nil }
        let value = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        return duration.map { min(value, $0) } ?? value
    }
}

/// The "now playing" scene: a slowly turning blur of the cover, the cover with a soft
/// soft shadow, an eyebrow with a live equaliser, title, artist, and a
/// timeline that glides continuously.
///
/// Everything that moves is a Core Animation animation: the system renders it smoothly
/// with no per-frame work here, at a capped frame rate. The timeline is one linear
/// animation from the current position to the end of the song, re-synced only when the
/// song, position or play state changes, so it moves like a watch's second hand.
private final class NowPlayingScene: CALayer {
    var scale: CGFloat = 2 {
        didSet { textLayers.forEach { $0.contentsScale = scale } }
    }

    private let backdrop = CALayer()
    private let backdropTwin = CALayer()
    private let shade = CAGradientLayer()
    private let vignette = CAGradientLayer()
    private let grain = CALayer()
    private let content = CALayer()
    private let shadow = CALayer()
    private let cover = CALayer()
    private let equalizer = CALayer()
    private let bars = (0..<3).map { _ in CALayer() }
    private let eyebrow = CATextLayer()
    private let title = CATextLayer()
    private let artist = CATextLayer()
    private let track = CALayer()
    private let fill = CALayer()
    private let elapsed = CATextLayer()
    private let remaining = CATextLayer()
    private var textLayers: [CATextLayer] { [eyebrow, title, artist, elapsed, remaining] }

    private var artworkFile: String?
    private var coverAspect: CGFloat = 1
    private var lastCard: Card?
    private var syncedCard: Card?
    private var syncedWidth: CGFloat = 0
    private var labelSecond = -1
    private var motion = false
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// Slow ambient motion doesn't need the display's full refresh rate.
    private static let ambientRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)

    override init() {
        super.init()
        backgroundColor = NSColor.black.cgColor
        for layer in [backdrop, backdropTwin] {
            layer.contentsGravity = .resizeAspectFill
        }
        backdropTwin.opacity = 0.55
        backdropTwin.compositingFilter = "screenBlendMode"
        shade.colors = [NSColor.black.withAlphaComponent(0.2).cgColor, NSColor.black.withAlphaComponent(0.35).cgColor,
                        NSColor.black.withAlphaComponent(0.72).cgColor]
        shade.locations = [0, 0.5, 1]
        vignette.type = .radial
        vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.55).cgColor]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.15, y: 1.15)
        grain.backgroundColor = Self.grainPattern
        grain.opacity = 0.5
        grain.compositingFilter = "overlayBlendMode"

        // Shadow only: the plate itself is invisible, so nothing shows around the cover.
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOpacity = 0.35
        cover.contentsGravity = .resizeAspectFill
        cover.masksToBounds = true
        cover.cornerCurve = .continuous
        cover.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        cover.borderWidth = 0.5

        for bar in bars {
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.75).cgColor
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            equalizer.addSublayer(bar)
        }
        track.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        fill.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        fill.anchorPoint = .zero
        track.addSublayer(fill)
        for layer in textLayers {
            layer.contentsScale = scale
            layer.truncationMode = .end
            layer.isWrapped = false
        }
        [eyebrow, title, artist].forEach { $0.alignmentMode = .center }
        elapsed.alignmentMode = .left
        remaining.alignmentMode = .right

        [backdrop, backdropTwin, shade, vignette, grain, content].forEach(addSublayer)
        [shadow, cover, equalizer, eyebrow, title, artist, track, elapsed, remaining].forEach(content.addSublayer)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Updates

    func update(card: Card, directory: URL?, now: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if card.artworkFile != artworkFile, let directory {
            artworkFile = card.artworkFile
            let image = card.artworkFile.map { directory.appendingPathComponent($0) }
                .flatMap { NSImage(contentsOf: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            // Song change: crossfade cover and backdrop.
            if lastCard != nil {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.9
                [cover, backdrop, backdropTwin].forEach { $0.add(fade, forKey: "contents") }
            }
            cover.contents = image
            coverAspect = image.map { min(max(CGFloat($0.width) / CGFloat(max($0.height, 1)), 1), 16.0 / 9.0) } ?? 1
            let blurred = image.flatMap { Self.blurred($0, size: 220, sigma: 12) }
            backdrop.contents = blurred
            backdropTwin.contents = blurred
            setNeedsLayout()
        }
        let structureChanged = card.title != lastCard?.title || card.artist != lastCard?.artist
            || card.isPlaying != lastCard?.isPlaying || card.playerName != lastCard?.playerName
            || (card.duration ?? 0).isZero != (lastCard?.duration ?? 0).isZero
        lastCard = card
        if structureChanged {
            setText()
            setNeedsLayout()
        }
        updateLabels(now: now)
        CATransaction.commit()
        syncTimeline(now: now)
        updateEqualizer()
    }

    private func setText() {
        guard let card = lastCard else { return }
        let unit = min(bounds.width, bounds.height)
        let source = card.playerName.map { " · \($0.uppercased())" } ?? ""
        eyebrow.string = NSAttributedString(string: (card.isPlaying ? "NOW PLAYING" : "PAUSED") + source, attributes: [
            .font: NSFont.systemFont(ofSize: unit * 0.0125, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .kern: unit * 0.0125 * 0.14,
        ])
        title.string = NSAttributedString(string: card.title, attributes: [
            .font: NSFont.systemFont(ofSize: unit * 0.036, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.96),
            .kern: -unit * 0.036 * 0.022,
        ])
        artist.string = NSAttributedString(string: card.artist, attributes: [
            .font: NSFont.systemFont(ofSize: unit * 0.021, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ])
        cover.borderColor = NSColor.white.withAlphaComponent(card.isPlaying ? 0.12 : 0.06).cgColor
    }

    /// Labels change exactly when the displayed second does.
    private func updateLabels(now: Date) {
        guard let card = lastCard, let duration = card.duration, duration > 0, let position = card.position(at: now) else { return }
        let second = Int(position)
        guard second != labelSecond else { return }
        labelSecond = second
        let unit = min(bounds.width, bounds.height)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: unit * 0.0135, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5),
        ]
        elapsed.string = NSAttributedString(string: Self.format(Double(second)), attributes: attributes)
        remaining.string = NSAttributedString(string: "-" + Self.format(max(0, duration - Double(second))), attributes: attributes)
    }

    /// One linear animation to the end of the song; only restarted when the card changes.
    private func syncTimeline(now: Date) {
        guard let card = lastCard, let duration = card.duration, duration > 0, let position = card.position(at: now) else { return }
        let width = track.bounds.width
        // Re-sync when the card or size changed, or if the system dropped the animation
        // (e.g. after display sleep).
        let lostAnimation = card.isPlaying && fill.animation(forKey: "progress") == nil && position < duration
        guard width > 0, card != syncedCard || width != syncedWidth || lostAnimation else { return }
        syncedCard = card
        syncedWidth = width
        let fraction = min(max(position / duration, 0), 1)
        let startWidth = width * fraction
        fill.removeAnimation(forKey: "progress")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The resting value is "now", so a dropped animation never jumps to the end.
        fill.bounds.size.width = startWidth
        CATransaction.commit()
        guard card.isPlaying, fraction < 1 else { return }
        let glide = CABasicAnimation(keyPath: "bounds.size.width")
        glide.fromValue = startWidth
        glide.toValue = width
        glide.duration = duration - position
        glide.fillMode = .forwards
        glide.isRemovedOnCompletion = false
        glide.timingFunction = CAMediaTimingFunction(name: .linear)
        // Full display refresh rate, like a second hand; it's a tiny layer.
        glide.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        fill.add(glide, forKey: "progress")
    }

    // MARK: Layout

    override func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // A square big enough to stay full-screen while it turns.
        let diagonal = hypot(bounds.width, bounds.height) * 1.1
        for layer in [backdrop, backdropTwin] {
            layer.bounds = CGRect(x: 0, y: 0, width: diagonal, height: diagonal)
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        [shade, vignette, grain].forEach { $0.frame = bounds }
        content.bounds = bounds
        content.position = CGPoint(x: bounds.midX, y: bounds.midY)

        // The lock screen draws its clock over the top ~30% and the user picture and
        // password prompt over the bottom ~17%; everything sits between, centred.
        let unit = min(bounds.width, bounds.height)
        let hasTimeline = !(lastCard?.duration ?? 0).isZero
        let eyebrowHeight = unit * 0.02, titleHeight = unit * 0.05, artistHeight = unit * 0.032
        let timelineHeight = hasTimeline ? unit * 0.05 : 0
        let textBlock = unit * 0.045 + eyebrowHeight + unit * 0.008 + titleHeight + artistHeight + timelineHeight
        let regionBottom = bounds.height * 0.17, regionTop = bounds.height * 0.70
        let coverHeight = max(unit * 0.12, min(unit * 0.34, regionTop - regionBottom - textBlock))
        let coverSize = CGSize(width: coverHeight * coverAspect, height: coverHeight)
        let column = max(coverSize.width, unit * 0.25)
        let left = bounds.midX - column / 2
        var y = regionBottom + (regionTop - regionBottom + coverSize.height + textBlock) / 2 - coverSize.height

        cover.frame = CGRect(x: bounds.midX - coverSize.width / 2, y: y, width: coverSize.width, height: coverSize.height)
        cover.cornerRadius = coverHeight * 0.045
        shadow.frame = cover.frame
        shadow.shadowPath = CGPath(roundedRect: shadow.bounds, cornerWidth: cover.cornerRadius, cornerHeight: cover.cornerRadius, transform: nil)
        shadow.shadowRadius = unit * 0.03
        shadow.shadowOffset = CGSize(width: 0, height: -unit * 0.01)

        y -= unit * 0.045 + eyebrowHeight
        let eyebrowWidth = column
        eyebrow.frame = CGRect(x: left, y: y, width: eyebrowWidth, height: eyebrowHeight)
        // Equaliser to the left of the eyebrow text.
        let textWidth = (eyebrow.string as? NSAttributedString)?.size().width ?? 0
        let barWidth = max(1.5, unit * 0.0024), barGap = barWidth * 0.9, barHeight = eyebrowHeight * 0.62
        let eqWidth = barWidth * 3 + barGap * 2
        let eqX = bounds.midX - textWidth / 2 - eqWidth - unit * 0.008
        equalizer.frame = CGRect(x: eqX, y: y + eyebrowHeight * 0.2, width: eqWidth, height: barHeight)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barHeight)
            bar.position = CGPoint(x: barWidth / 2 + CGFloat(i) * (barWidth + barGap), y: 0)
            bar.cornerRadius = barWidth / 2
        }
        y -= unit * 0.008 + titleHeight
        title.frame = CGRect(x: bounds.midX - column * 0.75, y: y, width: column * 1.5, height: titleHeight)
        y -= artistHeight
        artist.frame = CGRect(x: bounds.midX - column * 0.75, y: y, width: column * 1.5, height: artistHeight)

        track.isHidden = !hasTimeline
        elapsed.isHidden = !hasTimeline
        remaining.isHidden = !hasTimeline
        if hasTimeline {
            y -= unit * 0.025
            track.frame = CGRect(x: left, y: y, width: column, height: max(3, unit * 0.0045))
            track.cornerRadius = track.bounds.height / 2
            fill.frame = CGRect(x: 0, y: 0, width: fill.bounds.width, height: track.bounds.height)
            fill.cornerRadius = track.cornerRadius
            y -= unit * 0.025
            elapsed.frame = CGRect(x: left, y: y, width: column / 2, height: unit * 0.02)
            remaining.frame = CGRect(x: left + column / 2, y: y, width: column / 2, height: unit * 0.02)
        }
        CATransaction.commit()
        setText()
        labelSecond = -1
        updateLabels(now: Date())
        syncTimeline(now: Date())
    }

    // MARK: Motion

    func startMotion() {
        motion = true
        syncedCard = nil
        syncTimeline(now: Date())
        guard !reduceMotion else { return }
        // Backdrop: two copies of the blur turning slowly in opposite directions.
        for (layer, (duration, direction)) in zip([backdrop, backdropTwin], [(200.0, 1.0), (150.0, -1.0)])
        where layer.animation(forKey: "turn") == nil {
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = direction * 2 * Double.pi
            turn.duration = duration
            turn.repeatCount = .infinity
            turn.preferredFrameRateRange = Self.ambientRate
            layer.add(turn, forKey: "turn")
            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 1
            breathe.toValue = 1.12
            breathe.duration = duration / 4
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathe.preferredFrameRateRange = Self.ambientRate
            layer.add(breathe, forKey: "breathe")
        }
        // Content: a very slow vertical drift so nothing sits still on the display for
        // hours. Never sideways: it must stay centred under the lock screen clock.
        if content.animation(forKey: "drift") == nil {
            let d = min(bounds.width, bounds.height) * 0.008
            let drift = CABasicAnimation(keyPath: "position.y")
            drift.fromValue = bounds.midY + d
            drift.toValue = bounds.midY - d
            drift.duration = 120
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drift.preferredFrameRateRange = Self.ambientRate
            content.add(drift, forKey: "drift")
        }
        updateEqualizer()
    }

    func stopMotion() {
        motion = false
        [backdrop, backdropTwin].forEach { $0.removeAllAnimations() }
        content.removeAnimation(forKey: "drift")
        updateEqualizer()
    }

    /// Three bars bouncing out of phase while playing; still and short when paused.
    private func updateEqualizer() {
        let playing = motion && !reduceMotion && (lastCard?.isPlaying ?? false)
        for (i, bar) in bars.enumerated() {
            if playing {
                guard bar.animation(forKey: "bounce") == nil else { continue }
                let bounce = CAKeyframeAnimation(keyPath: "transform.scale.y")
                bounce.values = [[0.35, 1, 0.55, 0.85, 0.35], [0.8, 0.4, 1, 0.5, 0.8], [0.5, 0.9, 0.3, 1, 0.5]][i]
                bounce.duration = [1.1, 0.9, 1.3][i]
                bounce.repeatCount = .infinity
                bounce.calculationMode = .cubic
                bounce.preferredFrameRateRange = Self.ambientRate
                bar.add(bounce, forKey: "bounce")
            } else {
                bar.removeAnimation(forKey: "bounce")
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.transform = CATransform3DMakeScale(1, 0.35, 1)
                CATransaction.commit()
            }
        }
    }

    // MARK: Images

    private static func blurred(_ image: CGImage, size: CGFloat, sigma: Double, exposure: Double = -0.85) -> CGImage? {
        var input = CIImage(cgImage: image)
        let scale = size / max(input.extent.width, input.extent.height, 1)
        input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = input.extent
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
            .cropped(to: extent)
        return context.createCGImage(output, from: extent)
    }

    /// Fine static film grain, tiled, so the dark gradients don't band.
    private static let grainPattern: CGColor? = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            let v = UInt8(Int.random(in: 100...156) * 36 / 255)
            pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v; pixels[i * 4 + 3] = 36
        }
        let image = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return image.map { NSColor(patternImage: NSImage(cgImage: $0, size: NSSize(width: side / 2, height: side / 2))).cgColor }
    }()

    private static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
