import SleeveCore
import SleeveGlow
import SwiftUI

/// SwiftUI wrapper around the engine-backed preview.
struct GlowPreview: NSViewRepresentable {
    var configuration: GlowPreviewNSView.Configuration
    var onSignalChange: ((Bool) -> Void)?
    @Environment(AppEnvironment.self) private var env

    func makeNSView(context: Context) -> GlowPreviewNSView {
        let view = GlowPreviewNSView(stream: env.stream)
        view.configuration = configuration
        view.onSignalChange = onSignalChange
        return view
    }

    func updateNSView(_ view: GlowPreviewNSView, context: Context) {
        view.configuration = configuration
        view.onSignalChange = onSignalChange
    }
}

/// A stylised Mac display: bezel, desktop with a couple of windows, and the live glow.
struct DevicePreview: View {
    var configuration: GlowPreviewNSView.Configuration
    var palette: ArtworkPalette
    var onSignalChange: ((Bool) -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            ZStack {
                // Desktop
                LinearGradient(colors: [palette.background.color, Color(white: 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)
                FakeDesktopWindows()
                GlowPreview(configuration: configuration, onSignalChange: onSignalChange)
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .padding(10)
        }
        .aspectRatio(16.0 / 10.4, contentMode: .fit)
        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
    }
}

/// Placeholder app windows so it's clear the glow sits around, not over, your work.
private struct FakeDesktopWindows: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                window(width: w * 0.46, height: h * 0.52).offset(x: w * 0.12, y: h * 0.2)
                window(width: w * 0.34, height: h * 0.42).offset(x: w * 0.5, y: h * 0.34)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func window(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.18)).frame(width: 5, height: 5) }
            }
            .padding(6)
            Spacer()
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.07), lineWidth: 0.5) }
    }
}
