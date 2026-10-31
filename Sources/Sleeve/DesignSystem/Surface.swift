import AppKit
import SwiftUI

/// The single surface API feature code uses. Liquid Glass on macOS 26+,
/// a behind-window material with a hairline on macOS 14–15.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                tint.map { .regular.tint($0.opacity(0.25)) } ?? .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content
                .background {
                    ZStack {
                        VisualEffectBackground(material: .hudWindow)
                        if let tint { tint.opacity(0.12) }
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                }
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = DS.Radius.lg, tint: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
