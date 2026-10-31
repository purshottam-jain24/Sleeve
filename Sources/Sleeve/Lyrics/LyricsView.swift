import AfterglowCore
import SwiftUI

/// Time-synced lyrics in one of three styles. Lines are clickable to seek.
struct LyricsView: View {
    var document: LyricsDocument
    var style: LyricsDisplayStyle
    var fontSize: CGFloat
    var palette: ArtworkPalette
    var translations: [Int: String]
    var duration: TimeInterval?
    var isPlaying: Bool
    var position: (Date) -> TimeInterval?
    var onSeek: (TimeInterval) -> Void

    @State private var activeIndex: Int?

    var body: some View {
        ZStack {
            // Wakes only at upcoming line boundaries (and never while paused) instead of
            // polling; the schedule is rebuilt whenever playback state changes.
            TimelineView(LineSchedule(dates: upcomingLineDates())) { context in
                let index = position(context.date).flatMap(document.lineIndex(at:))
                Color.clear.onChange(of: index, initial: true) { _, new in
                    withAnimation(DS.Motion.lyric) { activeIndex = new }
                }
            }
            switch style {
            case .focus, .karaoke:
                ScrollingLyrics(
                    document: document, activeIndex: activeIndex, karaoke: style == .karaoke && isPlaying,
                    fontSize: fontSize, palette: palette, translations: translations,
                    duration: duration, position: position, onSeek: onSeek
                )
            case .glow:
                GlowLyrics(
                    document: document, activeIndex: activeIndex, fontSize: fontSize,
                    palette: palette, translations: translations
                )
            }
        }
    }
}

extension LyricsView {
    /// Wall-clock times of the next line starts, valid until playback state changes.
    func upcomingLineDates(limit: Int = 64) -> [Date] {
        let now = Date()
        guard isPlaying, let position = position(now) else { return [now] }
        var dates = [now]
        for line in document.synced where line.time > position {
            dates.append(now.addingTimeInterval(line.time - position + 0.01))
            if dates.count > limit { break }
        }
        return dates
    }
}

private struct LineSchedule: TimelineSchedule {
    var dates: [Date]
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        dates.filter { $0 >= startDate.addingTimeInterval(-0.5) }
    }
}

// MARK: Focus & Karaoke

private struct ScrollingLyrics: View {
    var document: LyricsDocument
    var activeIndex: Int?
    var karaoke: Bool
    var fontSize: CGFloat
    var palette: ArtworkPalette
    var translations: [Int: String]
    var duration: TimeInterval?
    var position: (Date) -> TimeInterval?
    var onSeek: (TimeInterval) -> Void

    @State private var userScrolledAt: Date = .distantPast

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: fontSize * 0.75) {
                        Color.clear.frame(height: geo.size.height * 0.32)
                        ForEach(document.synced) { line in
                            LyricRow(
                                line: line,
                                distance: activeIndex.map { abs(line.id - $0) } ?? (line.id + 1),
                                isActive: line.id == activeIndex,
                                isPast: activeIndex.map { line.id < $0 } ?? false,
                                karaoke: karaoke,
                                fontSize: fontSize,
                                palette: palette,
                                translation: translations[line.id],
                                progress: { date in
                                    guard let p = position(date) else { return 0 }
                                    return LyricRow.progress(of: line, in: document, at: p, duration: duration)
                                },
                                onSeek: { onSeek(line.time) }
                            )
                            .id(line.id)
                        }
                        Color.clear.frame(height: geo.size.height * 0.6)
                    }
                    .padding(.horizontal, DS.Space.s2)
                }
                .modifier(ScrollInteractionTracker(lastInteraction: $userScrolledAt))
                .mask(EdgeFade())
                .onChange(of: activeIndex, initial: true) { _, index in
                    // Respect manual scrolling for a few seconds before following again.
                    guard let index, Date().timeIntervalSince(userScrolledAt) > 4 else { return }
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) {
                        proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.32))
                    }
                }
            }
        }
    }
}

private struct ScrollInteractionTracker: ViewModifier {
    @Binding var lastInteraction: Date

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { lastInteraction = Date() }
            }
        } else {
            content
        }
    }
}

private struct LyricRow: View {
    var line: LyricLine
    var distance: Int
    var isActive: Bool
    var isPast: Bool
    var karaoke: Bool
    var fontSize: CGFloat
    var palette: ArtworkPalette
    var translation: String?
    var progress: (Date) -> Double
    var onSeek: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if line.isGap {
                GapDots(isActive: isActive, size: fontSize * 0.35)
            } else if karaoke && isActive {
                TimelineView(.animation) { context in
                    KaraokeText(text: line.text, progress: progress(context.date), fontSize: fontSize, palette: palette)
                }
            } else {
                Text(line.text)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(opacity))
            }
            if let translation, !line.isGap {
                Text(translation)
                    .font(.system(size: fontSize * 0.52, weight: .medium))
                    .foregroundStyle(.white.opacity(isActive ? 0.7 : opacity * 0.8))
            }
        }
        .blur(radius: isActive || hovering ? 0 : min(2.6, Double(distance) * 0.7))
        .scaleEffect(isActive ? 1 : 0.95, anchor: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(.white.opacity(hovering ? 0.06 : 0), in: .rect(cornerRadius: DS.Radius.sm))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSeek)
        .animation(DS.Motion.lyric, value: isActive)
        .animation(DS.Motion.snappy, value: hovering)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Plays from this line")
    }

    private var opacity: Double {
        if isActive { return 1 }
        if hovering { return 0.75 }
        return isPast ? 0.28 : 0.38
    }

    /// Word-timed when the source has word timings; otherwise spread across the line.
    static func progress(of line: LyricLine, in document: LyricsDocument, at position: TimeInterval, duration: TimeInterval?) -> Double {
        let lineProgress = document.progress(ofLine: line.id, at: position, trackDuration: duration)
        guard !line.words.isEmpty else { return lineProgress }
        let total = line.words.reduce(0) { $0 + $1.text.count }
        guard total > 0 else { return lineProgress }
        var sung = 0.0
        for (i, word) in line.words.enumerated() where position >= word.time {
            let end = i + 1 < line.words.count ? line.words[i + 1].time : word.time + 0.6
            let f = min(1, (position - word.time) / max(0.05, end - word.time))
            sung += Double(word.text.count) * f
        }
        return sung / Double(total)
    }
}

/// Text whose sung part is lit in the album's colour with a soft leading edge.
private struct KaraokeText: View {
    var text: String
    var progress: Double
    var fontSize: CGFloat
    var palette: ArtworkPalette

    var body: some View {
        let base = Text(text).font(.system(size: fontSize, weight: .bold))
        base
            .foregroundStyle(.white.opacity(0.4))
            .overlay(alignment: .leading) {
                base
                    .foregroundStyle(LinearGradient(colors: [.white, palette.glowColors[0].color], startPoint: .leading, endPoint: .trailing))
                    .shadow(color: palette.glowColors[0].color.opacity(0.6), radius: 12)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            LinearGradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: max(0, progress - 0.02)),
                                .init(color: .clear, location: min(1, progress + 0.04)),
                            ], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width)
                        }
                    }
            }
    }
}

private struct GapDots: View {
    var isActive: Bool
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(isActive ? 0.9 : 0.3))
                    .frame(width: size, height: size)
                    .scaleEffect(isActive ? 1 : 0.8)
                    .animation(isActive ? .easeInOut(duration: 0.8).repeatForever().delay(Double(i) * 0.2) : .default, value: isActive)
            }
        }
        .accessibilityLabel("Instrumental break")
    }
}

// MARK: Glow

/// One luminous line at a time, with the next line waiting below.
private struct GlowLyrics: View {
    var document: LyricsDocument
    var activeIndex: Int?
    var fontSize: CGFloat
    var palette: ArtworkPalette
    var translations: [Int: String]

    var body: some View {
        let lines = document.synced
        let current = activeIndex.flatMap { lines.indices.contains($0) ? lines[$0] : nil }
        let nextIndex = (activeIndex ?? -1) + 1
        let next = lines.indices.contains(nextIndex) ? lines[nextIndex] : nil
        let glow = palette.glowColors[0].color

        VStack(spacing: fontSize * 0.6) {
            Group {
                if let current, !current.isGap {
                    VStack(spacing: 8) {
                        Text(current.text)
                            .font(.system(size: fontSize * 1.15, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: glow.opacity(0.9), radius: 18)
                            .shadow(color: glow.opacity(0.5), radius: 42)
                        if let translation = translations[current.id] {
                            Text(translation)
                                .font(.system(size: fontSize * 0.55, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                } else {
                    GapDots(isActive: true, size: fontSize * 0.4)
                }
            }
            .id(activeIndex ?? -1)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 28)).combined(with: .scale(scale: 0.96)),
                removal: .opacity.combined(with: .offset(y: -28))
            ))

            if let next, !next.isGap {
                Text(next.text)
                    .font(.system(size: fontSize * 0.62, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .id("next-\(next.id)")
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
