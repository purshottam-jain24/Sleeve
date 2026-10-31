import AfterglowCore
import SwiftUI

/// Album artwork with a palette-washed placeholder, crossfade on change and tinted shadow.
struct ArtworkView: View {
    var image: NSImage?
    var palette: ArtworkPalette
    var cornerRadius: CGFloat = DS.Radius.md
    var identity: String?

    var body: some View {
        ZStack {
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
        .shadow(color: palette.primary.color.opacity(0.35), radius: 14, y: 6)
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

    var body: some View {
        if let duration = snapshot.track?.duration, duration > 0 {
            TimelineView(.periodic(from: .now, by: snapshot.state == .playing ? 0.5 : 60)) { context in
                let position = snapshot.position(at: context.date) ?? 0
                let fraction = dragFraction ?? min(1, position / duration)
                VStack(spacing: DS.Space.s1) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.12))
                            Capsule().fill(tint).frame(width: max(4, proxy.size.width * fraction))
                        }
                        .frame(height: dragFraction == nil ? 4 : 6)
                        .frame(maxHeight: .infinity)
                        .contentShape(.rect)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    dragFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                                }
                                .onEnded { _ in
                                    if let dragFraction { onSeek(dragFraction * duration) }
                                    dragFraction = nil
                                }
                        )
                    }
                    .frame(height: 12)
                    .animation(DS.Motion.snappy, value: dragFraction == nil)

                    HStack {
                        Text(format(fraction * duration))
                        Spacer()
                        Text("-" + format(duration - fraction * duration))
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Playback position")
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct VolumeSlider: View {
    var volume: Double
    var onChange: (Double) -> Void
    @State private var local: Double?

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { local ?? volume }, set: { local = $0 }),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing, let local {
                        onChange(local)
                        self.local = nil
                    }
                }
            )
            .controlSize(.mini)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Volume")
    }
}
