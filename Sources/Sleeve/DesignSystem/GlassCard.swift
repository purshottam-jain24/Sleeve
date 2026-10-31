import SwiftUI

/// A titled container on a glass surface, used for every settings group.
struct GlassCard<Content: View>: View {
    var title: String
    var symbol: String
    var caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 6))
                Text(title).font(DS.Font.sectionTitle)
                Spacer(minLength: 0)
            }
            content
            if let caption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.045), in: .rect(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }
}

/// Labelled slider with a live value readout.
struct ValueSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: (Double) -> String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
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

/// Round glass button for transport controls.
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
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(isHovering ? 0.16 : 0.09)))
                }
                .overlay { Circle().strokeBorder(.white.opacity(prominent ? 0 : 0.12), lineWidth: 0.5) }
                .scaleEffect(isHovering ? 1.05 : 1)
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

/// Small rounded status chip.
struct StatusPill: View {
    var text: String
    var symbol: String
    var color: Color = .secondary

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.07), in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5) }
    }
}
