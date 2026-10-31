import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders soft alpha masks for the glow layers.
///
/// Blurred masks are rendered at reduced resolution (a 150 pt blur gains nothing from
/// Retina pixels) and only when geometry or style changes — never per frame.
enum GlowMaskRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// - Parameters:
    ///   - inwardWidth: how far the lit band reaches into the screen, in points.
    ///   - blur: Gaussian radius in points.
    ///   - scale: render scale relative to points (e.g. 0.25).
    static func mask(geometry: GlowGeometry, inwardWidth: CGFloat, blur: CGFloat, scale: CGFloat) -> CGImage? {
        let width = max(1, Int((geometry.size.width * scale).rounded()))
        let height = max(1, Int((geometry.size.height * scale).rounded()))
        guard let gray = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        gray.setFillColor(gray: 0, alpha: 1)
        gray.fill(CGRect(x: 0, y: 0, width: width, height: height))
        gray.addPath(geometry.path(scale: scale))
        gray.setStrokeColor(gray: 1, alpha: 1)
        // The path runs along the very edge, so half the stroke is off-canvas.
        gray.setLineWidth(max(1, inwardWidth * 2 * scale))
        gray.setLineJoin(.round)
        gray.setLineCap(.round)
        gray.strokePath()
        guard let stroked = gray.makeImage() else { return nil }

        var image = CIImage(cgImage: stroked)
        let extent = image.extent
        let radius = blur * scale
        if radius > 0.5 {
            // Clamping continues the lit edge beyond the canvas, so the blur does not
            // darken the outermost pixels.
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image.clampedToExtent()
            filter.radius = Float(radius)
            image = filter.outputImage?.cropped(to: extent) ?? image
        }
        let toAlpha = CIFilter.maskToAlpha()
        toAlpha.inputImage = image
        guard let output = toAlpha.outputImage else { return nil }
        // Half-float RGBA (black, alpha = coverage): mask layers only read alpha, and
        // 16-bit alpha removes the banding an 8-bit mask shows across a wide falloff.
        return context.createCGImage(output, from: extent, format: .RGBAh, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    }
}
