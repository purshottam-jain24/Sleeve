import SleeveCore
import SwiftUI

/// Album artwork with a palette-washed placeholder, crossfade on change, a hairline edge
/// and a neutral shadow (colour belongs to the artwork, not a glow around it).
struct ArtworkView: View {
    var image: NSImage?
    var palette: ArtworkPalette
    var cornerRadius: CGFloat = DS.Radius.md
    var identity: String?

    /// Width ÷ height of the artwork. Video thumbnails are wide; album art is square.
    static func aspectRatio(of image: NSImage?) -> CGFloat {
        guard let size = image?.size, size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    var body: some View {
        // The image fills whatever frame the caller gives and is cropped to it; it must
        // never size the view itself (wide thumbnails would push the layout sideways).
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    LinearGradient(
                        colors: [palette.primary.color.opacity(0.55), palette.background.color],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        .id(identity)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .animation(DS.Motion.artwork, value: identity)
        .accessibilityHidden(image == nil)
        .accessibilityLabel("Album artwork")
    }
}

struct TransportButton: View {
    var systemName: String
    var size: CGFloat = 15
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct TransportControls: View {
    var isPlaying: Bool
    var isEnabled: Bool
    var perform: (PlaybackCommand) -> Void

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            TransportButton(systemName: "backward.fill", label: "Previous") { perform(.previous) }
            TransportButton(systemName: isPlaying ? "pause.fill" : "play.fill", size: 20, label: isPlaying ? "Pause" : "Play") {
                perform(.playPause)
            }
            TransportButton(systemName: "forward.fill", label: "Next") { perform(.next) }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Shows interpolated playback position; dragging seeks. Hidden when duration is unknown.
struct ProgressScrubber: View {
    var snapshot: PlaybackSnapshot
    var tint: Color
    var onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    /// The position the bar glides from. Kept across polls that only confirm it, so
    /// small timing differences in the player's reports never nudge the bar.
    @State private var anchor: Glide?

    var body: some View {
        if let duration = snapshot.track?.duration, duration > 0 {
            let glide = dragFraction.map { Glide(fraction: $0, date: .now, rate: 0) }
                ?? anchor ?? Glide(snapshot: snapshot, duration: duration)
            VStack(spacing: 6) {
                ThinTrack(fraction: glide.fraction, glide: glide, tint: tint) { dragFraction = $0 } onCommit: {
                    if let dragFraction { onSeek(dragFraction * duration) }
                    dragFraction = nil
                }
                // Labels tick exactly when the shown second changes, in step with the bar.
                TimelineView(glide.rate > 0 ? .periodic(from: glide.nextSecond(duration: duration), by: 1) : .periodic(from: .now, by: 3600)) { context in
                    let elapsed = Int((glide.fraction(at: context.date) * duration + 0.001).rounded(.down))
                    HStack {
                        Text(format(elapsed))
                        Spacer()
                        Text("-" + format(Int(duration.rounded(.down)) - elapsed))
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .onAppear { reanchor(duration: duration) }
            .onChange(of: snapshot) { reanchor(duration: duration) }
            .accessibilityElement()
            .accessibilityLabel("Playback position")
        }
    }

    private func reanchor(duration: TimeInterval) {
        let fresh = Glide(snapshot: snapshot, duration: duration)
        if let anchor, anchor.rate == fresh.rate, anchor.trackKey == fresh.trackKey,
           abs(anchor.fraction(at: .now) - fresh.fraction(at: .now)) * duration < 0.75 {
            return
        }
        anchor = fresh
    }

    private func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A linear run of the timeline: where it was at `date` and how fast it moves.
struct Glide: Equatable {
    var fraction: Double
    var date: Date
    /// Fraction of the track per second; 0 when paused.
    var rate: Double
    var trackKey: String?

    init(fraction: Double, date: Date, rate: Double, trackKey: String? = nil) {
        self.fraction = fraction
        self.date = date
        self.rate = rate
        self.trackKey = trackKey
    }

    init(snapshot: PlaybackSnapshot, duration: TimeInterval) {
        let now = Date()
        self.init(fraction: min(1, (snapshot.position(at: now) ?? 0) / duration), date: now,
                  rate: snapshot.state == .playing ? 1 / duration : 0, trackKey: snapshot.track?.cacheKey)
    }

    func fraction(at date: Date) -> Double {
        min(1, max(0, fraction + rate * date.timeIntervalSince(self.date)))
    }

    /// The moment the elapsed time next reaches a whole second.
    func nextSecond(duration: TimeInterval) -> Date {
        let seconds = fraction * duration
        return date.addingTimeInterval(seconds.rounded(.down) + 1 - seconds)
    }
}

/// A 3 pt track that thickens and shows a knob while hovered or dragged. With a `glide`,
/// the played part is animated by Core Animation (smooth at the display's refresh rate,
/// with no per-frame work in the app).
struct ThinTrack: View {
    var fraction: Double
    var glide: Glide?
    var tint: Color
    var onChange: (Double) -> Void
    var onCommit: () -> Void

    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let active = hovering || dragging
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                if let glide {
                    GlidingFill(glide: glide, color: NSColor(tint.opacity(active ? 1 : 0.85)))
                } else {
                    Capsule().fill(tint.opacity(active ? 1 : 0.85)).frame(width: max(3, width * fraction))
                }
            }
            .frame(height: active ? 5 : 3)
            // The knob is an overlay so its size never thickens the track. It follows the
            // glide frame by frame only while it's visible.
            .overlay(alignment: .leading) {
                TimelineView(.animation(paused: !active || (glide?.rate ?? 0) == 0)) { context in
                    let at = glide?.fraction(at: context.date) ?? fraction
                    Circle()
                        .fill(Color.white)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: min(max(0, width * at - 5.5), width - 11))
                }
                .opacity(active ? 1 : 0)
                .scaleEffect(active ? 1 : 0.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        onChange(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { _ in
                        dragging = false
                        onCommit()
                    }
            )
            .onHover { hovering = $0 }
            .animation(DS.Motion.snappy, value: active)
        }
        .frame(height: 14)
    }
}

struct VolumeSlider: View {
    var volume: Double
    var onChange: (Double) -> Void
    @State private var local: Double?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(DS.Palette.textTertiary)
            ThinTrack(fraction: local ?? volume, tint: DS.Palette.textSecondary) { local = $0 } onCommit: {
                if let local { onChange(local) }
                local = nil
            }
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundStyle(DS.Palette.textTertiary)
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((local ?? volume) * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            onChange(min(max(volume + step, 0), 1))
        }
    }
}

/// The played part of the timeline as a layer: one linear animation from the current
/// position to the end of the song, restarted only when the glide itself changes.
private struct GlidingFill: NSViewRepresentable {
    var glide: Glide
    var color: NSColor

    func makeNSView(context: Context) -> FillView { FillView() }

    func updateNSView(_ view: FillView, context: Context) {
        view.fill.backgroundColor = color.cgColor
        view.glide = glide
    }

    final class FillView: NSView {
        let fill = CALayer()
        var glide: Glide? {
            didSet { if glide != oldValue { sync() } }
        }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(fill)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            sync()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            sync()
        }

        private func sync() {
            guard let glide, window != nil else { return }
            let width = bounds.width, height = bounds.height
            guard width > 0 else { return }
            let current = glide.fraction(at: Date())
            let start = max(height, width * current)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.removeAnimation(forKey: "glide")
            fill.cornerRadius = height / 2
            fill.position = CGPoint(x: 0, y: height / 2)
            fill.bounds = CGRect(x: 0, y: 0, width: start, height: height)
            if glide.rate > 0, current < 1 {
                let animation = CABasicAnimation(keyPath: "bounds.size.width")
                animation.fromValue = start
                animation.toValue = width
                animation.duration = (1 - current) / glide.rate
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
                fill.add(animation, forKey: "glide")
            }
            CATransaction.commit()
        }
    }
}
