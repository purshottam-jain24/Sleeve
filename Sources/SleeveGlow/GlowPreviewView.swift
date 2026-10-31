import SleeveAudio
import SleeveCore
import AppKit
import QuartzCore

/// A miniature, live edge glow driven by the real engine, for Settings and preset cards.
///
/// Uses live system audio when it's available and a labelled demo signal otherwise.
/// Rendering stops while the window is hidden or occluded.
@MainActor
public final class GlowPreviewNSView: NSView {
    public struct Configuration: Equatable {
        public var settings: GlowSettings
        public var colors: [RGBAColor]
        public var isPlaying: Bool
        /// Width in points of the display this preview stands in for; style sizes scale by
        /// `bounds.width / referenceWidth`.
        public var referenceWidth: CGFloat
        public var showsNotch: Bool
        /// Small previews (preset cards) run at a lower frame rate to save power.
        public var maximumFrameRate: Float

        public init(settings: GlowSettings, colors: [RGBAColor], isPlaying: Bool, referenceWidth: CGFloat = 1512, showsNotch: Bool = true, maximumFrameRate: Float = 60) {
            self.settings = settings
            self.colors = colors
            self.isPlaying = isPlaying
            self.referenceWidth = referenceWidth
            self.showsNotch = showsNotch
            self.maximumFrameRate = maximumFrameRate
        }
    }

    public var configuration: Configuration? {
        didSet {
            guard configuration != oldValue else { return }
            needsLayout = true
            displayLink?.isPaused = false
            applyFrameRate()
        }
    }
    /// Reports whether the preview is currently showing live audio (vs. the demo signal).
    public var onSignalChange: ((Bool) -> Void)?

    private let glow = EdgeGlowView(frame: .zero)
    private let stream: AudioFeatureStream
    private var animator = GlowAnimator()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var demoTime: Double = 0
    private var showingLive = false

    public init(stream: AudioFeatureStream) {
        self.stream = stream
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(glow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var isStreamClient = false

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        if window != nil {
            if !isStreamClient { stream.addPreviewClient(); isStreamClient = true }
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            applyFrameRate()
        } else if isStreamClient {
            stream.removePreviewClient()
            isStreamClient = false
        }
    }

    private func applyFrameRate() {
        let rate = configuration?.maximumFrameRate ?? 60
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, rate), maximum: rate, preferred: rate)
    }

    public override func layout() {
        super.layout()
        glow.frame = bounds
        guard let configuration, bounds.width > 1, bounds.height > 1 else { return }
        let k = bounds.width / configuration.referenceWidth
        var style = configuration.settings.style
        style.thickness = max(1.2, style.thickness * k * 1.6)
        style.spread = max(6, style.spread * k * 1.4)
        var notch: CGRect?
        if configuration.showsNotch {
            let size = CGSize(width: bounds.width * 0.12, height: max(4, bounds.height * 0.032))
            notch = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - size.height, width: size.width, height: size.height)
        }
        let geometry = GlowGeometry(
            size: bounds.size,
            cornerRadius: max(2, configuration.settings.cornerRadius * k * 1.4),
            notch: notch,
            notchMode: configuration.settings.notchMode
        )
        glow.configure(geometry: geometry, style: style, hdr: configuration.settings.hdrHighlights, minimumMaskWidth: 320)
    }

    /// Skip work while hidden. A key window in the active app always renders, in case a
    /// transparent overlay (such as our own glow) is counted as covering it.
    private func isOnScreen(_ window: NSWindow) -> Bool {
        if Self.ignoresOcclusion { return true }
        return window.occlusionState.contains(.visible) || (NSApp.isActive && window.isKeyWindow)
    }

    /// Debug snapshot tours capture while the screen may be locked.
    private static let ignoresOcclusion = ProcessInfo.processInfo.environment["SLEEVE_SNAPSHOT_DIR"] != nil

    @objc private func tick(_ link: CADisplayLink) {
        guard let configuration, let window, isOnScreen(window) else { return }
        let now = link.timestamp
        let dt = lastTimestamp.map { min(now - $0, 0.1) } ?? 1.0 / 60
        lastTimestamp = now

        // Always advance the shared analyzer so a newly started song is noticed. Without
        // "Follow the beat", previews show the same gentle motion the real glow uses.
        let followBeat = configuration.settings.followBeat
        let liveFeatures = followBeat ? stream.features(at: now) : .silent
        let live = followBeat && stream.hasLiveSignal(at: now)
        let features: AudioFeatures
        demoTime += dt
        if live {
            features = liveFeatures
        } else if followBeat {
            features = DemoSignal.features(at: demoTime)
        } else {
            features = AmbientMotion.features(at: demoTime)
        }
        if live != showingLive {
            showingLive = live
            onSignalChange?(live)
        }

        let settings = configuration.settings
        let inputs = GlowInputs(
            style: settings.style,
            idleBehavior: settings.idleBehavior,
            colors: configuration.colors,
            // The demo stands in for playback so idle behaviour doesn't hide the preview.
            isPlaying: live ? configuration.isPlaying : true,
            audio: features,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            hdr: settings.hdrHighlights
        )
        glow.apply(animator.next(inputs, dt: dt))
    }
}
