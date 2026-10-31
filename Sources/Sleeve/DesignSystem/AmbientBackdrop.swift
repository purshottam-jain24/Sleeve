import SleeveCore
import CoreImage
import SwiftUI

/// Cinematic background: the artwork blown up and blurred, slow drifting light in the
/// album's colours, and a vignette that keeps text legible.
struct AmbientBackdrop: View {
    var artwork: NSImage?
    var palette: ArtworkPalette
    var identity: String?
    /// 0...1, how much colour shows through.
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DS.Palette.base
            palette.background.color.opacity(0.55)

            if let artwork, let blurred = BackdropBlur.image(for: artwork, key: identity) {
                // A tiny pre-blurred bitmap scaled up is visually identical to a live
                // 90 pt blur and costs nothing per frame. It lives in an overlay so its
                // fill size never becomes the backdrop's size: a wide video thumbnail
                // would otherwise widen the whole screen and push content under the sidebar.
                Color.clear.overlay {
                    Image(decorative: blurred, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.25)
                }
                .opacity(0.5 * intensity)
                .id(identity)
                .transition(.opacity)
            }

            DriftingLights(palette: palette, animated: !reduceMotion)
                .opacity(0.45 * intensity)
                .blendMode(.plusLighter)

            // Deep, even falloff: colour lives in the upper half, the bottom settles to
            // near-black so controls and lyrics read cleanly.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.2), location: 0),
                    .init(color: .black.opacity(0.4), location: 0.5),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center, startRadius: 240, endRadius: 1000)

            // Fine static grain keeps large dark gradients from banding and looking flat.
            FilmGrain().opacity(0.5)
        }
        .animation(.easeInOut(duration: 1.2), value: identity)
        .animation(.easeInOut(duration: 1.2), value: palette)
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A tiled, static monochrome noise texture, generated once.
private struct FilmGrain: View {
    var body: some View {
        if let tile = FilmGrain.tile {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }

    @MainActor static let tile: CGImage? = {
        let side = 192
        var rng = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            // Premultiplied: grey 96…160 at alpha 40/255.
            let v = UInt8(Int.random(in: 96...160, using: &rng) * 40 / 255)
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 40
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }()
}

/// Pre-blurs artwork once per track: downscale to 40 px, blur, boost saturation.
@MainActor
enum BackdropBlur {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static var cache: (key: String, image: CGImage)?

    static func image(for artwork: NSImage, key: String?) -> CGImage? {
        let cacheKey = key ?? "\(ObjectIdentifier(artwork))"
        if let cache, cache.key == cacheKey { return cache.image }
        guard let cg = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var image = CIImage(cgImage: cg)
        let scale = 40 / max(image.extent.width, 1)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        image = image.clampedToExtent()
            .applyingGaussianBlur(sigma: 3)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35])
            .cropped(to: extent)
        guard let output = context.createCGImage(image, from: extent) else { return nil }
        cache = (cacheKey, output)
        return output
    }
}

/// Three soft light sources that wander slowly.
///
/// Implemented with Core Animation: the drift runs in the system render server, so it
/// costs no main-thread work per frame. (SwiftUI-driven versions re-rendered the view
/// graph every frame and pinned a CPU core.)
private struct DriftingLights: NSViewRepresentable {
    var palette: ArtworkPalette
    var animated: Bool

    func makeNSView(context: Context) -> DriftingLightsView { DriftingLightsView() }

    func updateNSView(_ view: DriftingLightsView, context: Context) {
        view.update(colors: [palette.primary, palette.secondary, palette.tertiary], animated: animated)
    }
}

final class DriftingLightsView: NSView {
    private let lights = (0..<3).map { _ in CAGradientLayer() }
    private var colors: [RGBAColor] = []
    private var animated = true
    /// Start and end offsets (fractions of the light's diameter) and drift durations.
    private let paths: [(CGPoint, CGPoint, Double, CGFloat)] = [
        (CGPoint(x: -0.28, y: -0.22), CGPoint(x: 0.22, y: 0.12), 23, 1.2),
        (CGPoint(x: 0.3, y: 0.25), CGPoint(x: -0.12, y: -0.18), 29, 1.05),
        (CGPoint(x: 0.18, y: -0.3), CGPoint(x: -0.25, y: 0.28), 37, 0.95),
    ]

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for light in lights {
            light.type = .radial
            light.startPoint = CGPoint(x: 0.5, y: 0.5)
            light.endPoint = CGPoint(x: 1, y: 1)
            layer?.addSublayer(light)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(colors: [RGBAColor], animated: Bool) {
        let colorsChanged = colors != self.colors
        let motionChanged = animated != self.animated
        self.colors = colors
        self.animated = animated
        if colorsChanged {
            // Implicit 1.2 s crossfade between palettes.
            CATransaction.begin()
            CATransaction.setAnimationDuration(1.2)
            for (light, color) in zip(lights, colors) {
                light.colors = [color.withAlpha(0.42).cgColor, color.withAlpha(0).cgColor]
            }
            CATransaction.commit()
        }
        if motionChanged { needsLayout = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = max(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (light, path) in zip(lights, paths) {
            let (from, to, duration, scale) = path
            let diameter = side * scale
            light.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            let start = CGPoint(x: center.x + from.x * diameter, y: center.y + from.y * diameter)
            let end = CGPoint(x: center.x + to.x * diameter, y: center.y + to.y * diameter)
            light.position = start
            light.removeAnimation(forKey: "drift")
            if animated {
                let drift = CABasicAnimation(keyPath: "position")
                drift.fromValue = NSValue(point: start)
                drift.toValue = NSValue(point: end)
                drift.duration = duration
                drift.autoreverses = true
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                light.add(drift, forKey: "drift")
            }
        }
        CATransaction.commit()
    }
}
