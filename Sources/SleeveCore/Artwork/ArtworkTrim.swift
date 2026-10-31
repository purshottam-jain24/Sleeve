import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Removes flat bars around artwork. YouTube music videos often use a 16:9 thumbnail with
/// the square cover in the middle and plain bars either side; older thumbnails are 4:3
/// with black bars above and below.
public enum ArtworkTrim {
    /// The content rectangle (in pixels, top-left origin) when the image has matching flat
    /// bars on opposite sides; nil when there's nothing to trim.
    public static func contentRect(of image: CGImage) -> CGRect? {
        // Analyse a small copy; bars are large, smooth regions.
        let width = 160
        let height = max(8, Int((Double(image.height) / Double(image.width) * Double(width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        func pixel(_ x: Int, _ y: Int) -> SIMD3<Double> {
            let i = (y * width + x) * 4
            return SIMD3(Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
        }
        /// A flat line: every sample within `tolerance` of `reference`.
        func isFlat(_ samples: [SIMD3<Double>], like reference: SIMD3<Double>) -> Bool {
            samples.allSatisfy { s in
                let d = s - reference
                return max(abs(d.x), abs(d.y), abs(d.z)) < 14
            }
        }
        func column(_ x: Int) -> [SIMD3<Double>] { (1..<(height - 1)).map { pixel(x, $0) } }
        func row(_ y: Int) -> [SIMD3<Double>] { (1..<(width - 1)).map { pixel($0, y) } }

        func barWidth(count: Int, line: (Int) -> [SIMD3<Double>]) -> Int {
            let reference = line(0).reduce(SIMD3<Double>(), +) / Double(line(0).count)
            var n = 0
            while n < count / 2, isFlat(line(n), like: reference) { n += 1 }
            return n
        }

        let left = barWidth(count: width) { column($0) }
        let right = barWidth(count: width) { column(width - 1 - $0) }
        let top = barWidth(count: height) { row($0) }
        let bottom = barWidth(count: height) { row(height - 1 - $0) }

        func symmetric(_ a: Int, _ b: Int, of total: Int) -> Bool {
            a > total / 20 && b > total / 20 && abs(a - b) <= max(2, total / 40)
        }
        let sx = Double(image.width) / Double(width), sy = Double(image.height) / Double(height)
        var rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if symmetric(left, right, of: width) {
            rect.origin.x = (Double(left) + 1) * sx
            rect.size.width = Double(image.width) - (Double(left + right) + 2) * sx
        }
        if symmetric(top, bottom, of: height) {
            rect.origin.y = (Double(top) + 1) * sy
            rect.size.height = Double(image.height) - (Double(top + bottom) + 2) * sy
        }
        rect = rect.integral
        guard rect.width < CGFloat(image.width) || rect.height < CGFloat(image.height),
              rect.width > CGFloat(image.width) * 0.3, rect.height > CGFloat(image.height) * 0.3 else { return nil }
        return rect
    }

    /// JPEG data with flat bars removed, or nil when there were none.
    public static func trimmed(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rect = contentRect(of: image),
              let cropped = image.cropping(to: rect) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
