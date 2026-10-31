import AppKit
import CoreImage
import UniformTypeIdentifiers

/// Renders the "now playing" desktop picture: the artwork blurred and darkened as a
/// full-bleed backdrop, with the cover itself sharp in the middle. No text: the lock
/// screen draws its own track title and controls.
enum ArtworkWallpaper {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// - Parameters:
    ///   - pixelSize: the display size in pixels.
    /// - Returns: a JPEG in `directory`.
    static func render(_ artwork: CGImage, pixelSize: CGSize, into directory: URL) throws -> URL {
        let width = Int(pixelSize.width.rounded()), height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)

        // Backdrop: blur a small copy (cheap), then scale up; blur hides the upscale.
        if let backdrop = backdrop(from: artwork, aspect: pixelSize.width / pixelSize.height) {
            ctx.interpolationQuality = .high
            ctx.draw(backdrop, in: canvas)
        }
        let vignette = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.55)] as CFArray,
                                  locations: [0.35, 1])!
        let center = CGPoint(x: canvas.midX, y: canvas.midY)
        ctx.drawRadialGradient(vignette, startCenter: center, startRadius: 0, endCenter: center,
                               endRadius: hypot(canvas.width, canvas.height) / 2, options: [.drawsAfterEndLocation])

        // Cover: centred a little below the middle, clear of the lock screen clock.
        let artAspect = CGFloat(artwork.width) / CGFloat(max(artwork.height, 1))
        let side = min(canvas.height * 0.4, canvas.width * 0.32)
        let artSize = artAspect >= 1 ? CGSize(width: side * min(artAspect, 16.0 / 9.0), height: side)
                                     : CGSize(width: side, height: side / artAspect)
        let artRect = CGRect(x: canvas.midX - artSize.width / 2, y: canvas.height * 0.44 - artSize.height / 2,
                             width: artSize.width, height: artSize.height).integral
        let radius = min(artSize.width, artSize.height) * 0.035
        let path = CGPath(roundedRect: artRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.03), blur: side * 0.12, color: CGColor(gray: 0, alpha: 0.55))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(artwork, in: aspectFill(CGSize(width: artwork.width, height: artwork.height), in: artRect))
        ctx.restoreGState()

        guard let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("artwork-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    private static func backdrop(from artwork: CGImage, aspect: CGFloat) -> CGImage? {
        var image = CIImage(cgImage: artwork)
        let scale = 160 / max(image.extent.width, image.extent.height, 1)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // Crop to the display's shape so the blur fills the screen without stretching.
        let e = image.extent
        let crop = e.width / e.height > aspect
            ? CGRect(x: e.midX - e.height * aspect / 2, y: e.minY, width: e.height * aspect, height: e.height)
            : CGRect(x: e.minX, y: e.midY - e.width / aspect / 2, width: e.width, height: e.width / aspect)
        image = image.cropped(to: crop)
        let extent = image.extent
        image = image.clampedToExtent()
            .applyingGaussianBlur(sigma: 9)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15, kCIInputBrightnessKey: -0.12])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -0.9])
            .cropped(to: extent)
        return context.createCGImage(image, from: extent)
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
