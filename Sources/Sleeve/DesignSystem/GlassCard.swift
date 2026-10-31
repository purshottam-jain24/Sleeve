import SwiftUI

/// The app's one card surface: an opaque-enough body that's lit from above, a hairline
/// that's brighter on the top edge, and a soft shadow drawn from the shape only (never
/// the content, so it stays cheap while scrolling).
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = DS.Radius.card
    var isHighlighted = false
    var hasShadow = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(DS.Palette.cardBase)
                    .overlay { shape.fill(LinearGradient(colors: [DS.Palette.cardTop, DS.Palette.cardBottom], startPoint: .top, endPoint: .bottom)) }
                    .shadow(color: .black.opacity(hasShadow ? 0.3 : 0), radius: 16, y: 8)
            }
            .overlay {
                shape.strokeBorder(
                    isHighlighted
                        ? AnyShapeStyle(DS.Palette.accent.opacity(0.85))
                        : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)),
                    lineWidth: isHighlighted ? 1 : 0.75
                )
            }
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = DS.Radius.card, highlighted: Bool = false, shadow: Bool = true) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius, isHighlighted: highlighted, hasShadow: shadow))
    }
}

/// A small rounded square holding a card's glyph. Neutral on purpose: colour in Sleeve
/// comes from the music, so the chrome stays monochrome.
struct IconTile: View {
    var symbol: String
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(DS.Palette.textPrimary.opacity(0.85))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    }
            }
            .accessibilityHidden(true)
    }
}

/// A titled card: icon tile and title in a header row, an optional control on the right,
/// the content, and an optional footnote at the bottom.
struct GlassCard<Content: View, Accessory: View>: View {
    var title: String
    var symbol: String?
    var caption: String?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s3) {
                if let symbol { IconTile(symbol: symbol) }
                Text(title)
                    .font(DS.Font.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: DS.Space.s2)
                accessory
            }
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                content
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { RowDivider() }
            }
        }
        .padding(DS.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

extension GlassCard where Accessory == EmptyView {
    init(title: String, symbol: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, caption: caption, content: content) { EmptyView() }
    }
}

/// Hairline between rows inside a card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(DS.Palette.separator).frame(height: 0.5)
    }
}

/// Quiet label above a group of cards that aren't themselves in a card.
struct SectionLabel<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Font.sectionTitle)
                .tracking(DS.Tracking.sectionTitle)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 2)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// Cards in columns, each stacked tightly under the one above (no ragged row gaps).
/// Two columns when there's room, one when narrow. Cards go to columns in turn, so a card
/// that grows never jumps to another column.
struct MasonryLayout: Layout {
    var minColumnWidth: CGFloat = 330
    var maxColumns = 2
    var spacing: CGFloat = DS.Space.s4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minColumnWidth * CGFloat(maxColumns) + spacing
        return CGSize(width: width, height: arrange(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(width: bounds.width, subviews: subviews).frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let count = max(1, min(maxColumns, Int((width + spacing) / (minColumnWidth + spacing))))
        let columnWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        var bottoms = [CGFloat?](repeating: nil, count: count)
        var frames: [CGRect] = []
        for (index, subview) in subviews.enumerated() {
            let column = index % count
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let y = bottoms[column].map { $0 + spacing } ?? 0
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: y, width: columnWidth, height: height))
            bottoms[column] = y + height
        }
        return (frames, bottoms.compactMap { $0 }.max() ?? 0)
    }
}

/// Title, optional subtitle and an optional trailing control, shared by every page.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(DS.Font.pageTitle)
                    .tracking(DS.Tracking.pageTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            Spacer(minLength: DS.Space.s4)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A setting row: label and optional explanation on the left, a switch on the right.
struct SettingToggle: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.title).foregroundStyle(DS.Palette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// Low-emphasis button: a faint fill that brightens on hover.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration)
    }

    private struct QuietButton: View {
        var configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(configuration.isPressed ? 0.14 : hovering ? 0.1 : 0.065),
                            in: .rect(cornerRadius: DS.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(DS.Palette.hairline, lineWidth: 0.5)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
                .animation(DS.Motion.snappy, value: hovering)
        }
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

/// Labelled slider with a live value readout.
struct ValueSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: (Double) -> String
    var tint: Color = DS.Palette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(DS.Font.title).foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                Text(format(value))
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
        }
    }
}

/// Transport control: a plain glyph, with a faint disc on hover. `prominent` is the
/// play/pause button, which is larger and always fully opaque.
struct GlassIconButton: View {
    var systemName: String
    var diameter: CGFloat = 44
    var label: String
    var prominent = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * (prominent ? 0.5 : 0.4), weight: .regular))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(prominent ? DS.Palette.textPrimary : DS.Palette.textPrimary.opacity(isHovering ? 1 : 0.78))
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(Color.white.opacity(isHovering ? 0.08 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .animation(DS.Motion.snappy, value: isHovering)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }
}

/// Small status label: a coloured dot or symbol and quiet text, no chip.
struct StatusPill: View {
    var text: String
    var symbol: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            if symbol == "circle.fill" {
                Circle().fill(color).frame(width: 6, height: 6)
            } else {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
