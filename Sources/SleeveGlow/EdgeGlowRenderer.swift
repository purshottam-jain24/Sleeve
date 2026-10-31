import SleeveAudio
import SleeveCore
import AppKit
import QuartzCore

/// Click-through overlay window covering one display.
final class EdgeGlowWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Above the menu bar and Dock; shown on every Space and alongside full-screen apps.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Drives the edge glow on every selected display from a single display link.
@MainActor
public final class EdgeGlowRenderer: NSObject {
    public struct DisplayInfo: Identifiable, Hashable, Sendable {
        public let id: UInt32
        public let name: String
        public let isMain: Bool
    }

    private let stream: AudioFeatureStream
    private var audio: AudioCaptureService { stream.audio }
    private var animator = GlowAnimator()

    private var settings = GlowSettings()
    private var palette = ArtworkPalette.fallback
    private var isPlaying = false

    private var overlays: [UInt32: (window: EdgeGlowWindow, view: EdgeGlowView)] = [:]
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var wakeTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    public init(stream: AudioFeatureStream) {
        self.stream = stream
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        })
    }

    public static var availableDisplays: [DisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayInfo(id: screen.displayID, name: screen.localizedName, isMain: index == 0)
        }
    }

    public func update(settings: GlowSettings, palette: ArtworkPalette, isPlaying: Bool) {
        let previous = self.settings
        self.settings = settings
        self.palette = palette
        self.isPlaying = isPlaying

        if !settings.isEnabled {
            tearDown()
            return
        }
        if overlays.isEmpty || previous.displays != settings.displays
            || previous.notchMode != settings.notchMode || previous.cornerRadius != settings.cornerRadius {
            rebuildOverlays()
        } else {
            configureViews()
        }
        wake()
    }

    // MARK: Overlays

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch settings.displays {
        case .all: return screens
        case .main: return Array(screens.prefix(1))
        case .specific(let ids):
            let matching = screens.filter { ids.contains($0.displayID) }
            // If the chosen displays were unplugged, fall back to the main display.
            return matching.isEmpty ? Array(screens.prefix(1)) : matching
        }
    }

    private func rebuildOverlays() {
        guard settings.isEnabled else { return }
        let screens = targetScreens()
        let wanted = Set(screens.map(\.displayID))
        for (id, overlay) in overlays where !wanted.contains(id) {
            overlay.window.orderOut(nil)
            overlays.removeValue(forKey: id)
        }
        for screen in screens {
            if let existing = overlays[screen.displayID] {
                existing.window.setFrame(screen.frame, display: false)
                existing.view.frame = CGRect(origin: .zero, size: screen.frame.size)
            } else {
                let window = EdgeGlowWindow(screen: screen)
                let view = EdgeGlowView(frame: CGRect(origin: .zero, size: screen.frame.size))
                window.contentView = view
                window.orderFrontRegardless()
                overlays[screen.displayID] = (window, view)
            }
        }
        configureViews()
        recreateDisplayLink()
    }

    private func configureViews() {
        let screensByID = Dictionary(NSScreen.screens.map { ($0.displayID, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, overlay) in overlays {
            guard let screen = screensByID[id] else { continue }
            overlay.view.configure(geometry: geometry(for: screen), style: settings.style, hdr: settings.hdrHighlights)
        }
    }

    private func geometry(for screen: NSScreen) -> GlowGeometry {
        var notch: CGRect?
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // The auxiliary areas hug the screen's left and right edges; the notch is between them.
            let width = screen.frame.width - left.width - right.width
            if width > 0 {
                notch = CGRect(x: left.width, y: screen.frame.height - top, width: width, height: top)
            }
        }
        return GlowGeometry(
            size: screen.frame.size,
            cornerRadius: settings.cornerRadius,
            notch: notch,
            notchMode: settings.notchMode
        )
    }

    private func tearDown() {
        displayLink?.invalidate()
        displayLink = nil
        wakeTimer?.invalidate()
        wakeTimer = nil
        lastTimestamp = nil
        overlays.values.forEach { $0.window.orderOut(nil) }
        overlays.removeAll()
        animator = GlowAnimator()
    }

    // MARK: Frame loop

    private func recreateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        // Prefer the main display's view so the loop follows its refresh rate.
        let mainID = NSScreen.screens.first?.displayID
        guard let view = (mainID.flatMap { overlays[$0]?.view }) ?? overlays.values.first?.view else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Resumes rendering after any input change.
    private func wake() {
        guard settings.isEnabled else { return }
        wakeTimer?.invalidate()
        wakeTimer = nil
        setOverlaysVisible(true)
        if displayLink == nil { recreateDisplayLink() }
        displayLink?.isPaused = false
        lastTimestamp = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp.map { now - $0 } ?? 1.0 / 60
        lastTimestamp = now

        let style = settings.style
        // Without "Follow the beat" no audio is captured; music still gets gentle motion.
        let features: AudioFeatures = if !style.preset.usesAudio {
            .silent
        } else if settings.followBeat {
            stream.features(at: now)
        } else {
            isPlaying ? AmbientMotion.features(at: now) : .silent
        }

        let colors = style.useArtworkColors
            ? palette.glowColors
            : [style.primaryColor, style.secondaryColor]
        let inputs = GlowInputs(
            style: style,
            idleBehavior: settings.idleBehavior,
            colors: colors,
            isPlaying: isPlaying,
            audio: features,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            hdr: settings.hdrHighlights
        )
        var frame = animator.next(inputs, dt: dt)

        // Settled idle with breathing: draw one steady frame, let Core Animation breathe,
        // and stop the frame loop entirely.
        let handOffBreathing = frame.isSettledIdle && settings.idleBehavior == .breathe && !inputs.reduceMotion
        if handOffBreathing {
            var steady = inputs
            steady.idleBehavior = .steady
            var probe = animator
            frame = probe.next(steady, dt: 0)
            frame.needsContinuousUpdates = false
            overlays.values.forEach { $0.view.apply(frame); $0.view.startBreathing() }
        } else {
            overlays.values.forEach { $0.view.stopBreathing(); $0.view.apply(frame) }
        }

        let active = isPlaying || !features.isSilent
        let preferred: Float = active ? 60 : 30
        if link.preferredFrameRateRange.preferred != preferred {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: preferred)
        }

        // Fully idle and visually settled: stop the loop. If audio capture is running,
        // check twice a second for sound so non-detected players can wake the glow.
        let quiet = features.isSilent && features.level < 0.001 && !isPlaying
        let fullyHidden = frame.outerOpacity + frame.mediumOpacity + frame.bandOpacity + frame.highlightOpacity < 0.001
        if !frame.needsContinuousUpdates || (quiet && settings.idleBehavior == .hide && fullyHidden) {
            link.isPaused = true
            lastTimestamp = nil
            // Invisible overlays still cost compositing; take them off screen until needed.
            if fullyHidden { setOverlaysVisible(false) }
            scheduleAudioWakeCheck()
        }
    }

    private func setOverlaysVisible(_ visible: Bool) {
        for overlay in overlays.values where overlay.window.isVisible != visible {
            if visible { overlay.window.orderFrontRegardless() } else { overlay.window.orderOut(nil) }
        }
    }

    private func scheduleAudioWakeCheck() {
        guard wakeTimer == nil, settings.style.preset.usesAudio, audio.isRunning else { return }
        wakeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                var probe = [Float](repeating: 0, count: 512)
                let staleness = self.audio.buffer.copyLatest(into: &probe).staleness
                let peak = probe.map(abs).max() ?? 0
                if staleness < 0.5, peak > 1e-3 { self.wake() }
            }
        }
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
