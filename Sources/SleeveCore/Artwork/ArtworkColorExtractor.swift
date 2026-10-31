import CoreGraphics
import Foundation
import ImageIO

public struct ArtworkPalette: Sendable, Equatable {
    public var primary: RGBAColor
    public var secondary: RGBAColor
    public var tertiary: RGBAColor
    /// Dark, low-saturation tone suitable for cinematic backgrounds.
    public var background: RGBAColor
    /// `true` when the artwork has almost no colour (B&W photography, etc.).
    public var isMonochrome: Bool

    public init(primary: RGBAColor, secondary: RGBAColor, tertiary: RGBAColor, background: RGBAColor, isMonochrome: Bool) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.background = background
        self.isMonochrome = isMonochrome
    }

    public static let fallback = ArtworkPalette(
        primary: RGBAColor(red: 0.42, green: 0.36, blue: 1.0),
        secondary: RGBAColor(red: 1.0, green: 0.36, blue: 0.62),
        tertiary: RGBAColor(red: 0.25, green: 0.78, blue: 1.0),
        background: RGBAColor(red: 0.07, green: 0.06, blue: 0.10),
        isMonochrome: false
    )

    /// Bright, saturated versions for light emission (the edge glow).
    public var glowColors: [RGBAColor] {
        [primary, secondary, tertiary].map { color in
            let (h, s, b) = color.hsb
            if isMonochrome {
                return RGBAColor(hue: h, saturation: min(s, 0.15), brightness: 0.95)
            }
            return RGBAColor(hue: h, saturation: min(1, max(s, 0.55) * 1.1), brightness: max(b, 0.9))
        }
    }
}

/// Extracts a palette from artwork using k-means clustering on a 40×40 thumbnail.
///
/// Pure and deterministic: the same image always yields the same palette.
public struct ArtworkColorExtractor: Sendable {
    public var sampleSize = 40
    public var clusterCount = 6

    public init() {}

    public func palette(fromImageData data: Data) -> ArtworkPalette? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return palette(from: image)
    }

    public func palette(from image: CGImage) -> ArtworkPalette? {
        let pixels = samplePixels(image)
        guard !pixels.isEmpty else { return nil }

        let clusters = kMeans(pixels, k: min(clusterCount, pixels.count))
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
        let total = Double(pixels.count)

        var average = SIMD3<Double>.zero
        for p in pixels { average += p }
        average /= total

        let colorful = clusters.filter { $0.color.hsb.saturation > 0.18 && $0.color.hsb.brightness > 0.18 }
        let colorfulShare = colorful.reduce(0) { $0 + Double($1.count) } / total
        let isMonochrome = colorful.isEmpty || colorfulShare < 0.04

        // Favour frequent clusters, but give vivid colours a strong boost: a small
        // saturated accent usually reads as "the album's colour" more than a big grey.
        func score(_ c: Cluster) -> Double {
            let (_, s, b) = c.color.hsb
            let share = Double(c.count) / total
            let darkPenalty = b < 0.2 ? 0.2 : 1
            let washedPenalty = (s < 0.12 && b > 0.85) ? 0.4 : 1
            return pow(share, 0.55) * (0.25 + s * 1.6) * (0.4 + b * 0.6) * darkPenalty * washedPenalty
        }
        let ranked = (isMonochrome ? clusters : colorful).sorted { score($0) > score($1) }
        guard let primaryCluster = ranked.first else { return nil }
        let primary = primaryCluster.color

        func distinct(from used: [RGBAColor]) -> RGBAColor? {
            ranked.dropFirst().map(\.color).first { candidate in
                used.allSatisfy { hueDistance($0, candidate) > 0.07 || abs($0.hsb.brightness - candidate.hsb.brightness) > 0.35 }
            }
        }
        let (ph, ps, pb) = primary.hsb
        let secondary = distinct(from: [primary])
            ?? RGBAColor(hue: ph + 0.09, saturation: ps, brightness: max(pb * 0.85, 0.3))
        let tertiary = distinct(from: [primary, secondary])
            ?? RGBAColor(hue: ph - 0.09, saturation: ps * 0.9, brightness: max(pb, 0.4))

        let avg = RGBAColor(red: average.x, green: average.y, blue: average.z)
        let (ah, as_, _) = avg.hsb
        let background = RGBAColor(hue: ah, saturation: min(as_ * 0.9, 0.55), brightness: 0.12)

        return ArtworkPalette(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            background: background,
            isMonochrome: isMonochrome
        )
    }

    // MARK: Internals

    struct Cluster {
        var center: SIMD3<Double>
        var count: Int
        var color: RGBAColor { RGBAColor(red: center.x, green: center.y, blue: center.z) }
    }

    func samplePixels(_ image: CGImage) -> [SIMD3<Double>] {
        let size = sampleSize
        var buffer = [UInt8](repeating: 0, count: size * size * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return [] }
        var pixels: [SIMD3<Double>] = []
        pixels.reserveCapacity(size * size)
        for i in stride(from: 0, to: buffer.count, by: 4) where buffer[i + 3] > 200 {
            pixels.append(SIMD3(Double(buffer[i]), Double(buffer[i + 1]), Double(buffer[i + 2])) / 255)
        }
        return pixels
    }

    func kMeans(_ points: [SIMD3<Double>], k: Int, iterations: Int = 10) -> [Cluster] {
        guard k > 0 else { return [] }
        // Deterministic farthest-point initialisation.
        var centers = [points[points.count / 2]]
        while centers.count < k {
            var best = points[0]
            var bestDistance = -1.0
            for p in points {
                let d = centers.map { simdDistanceSquared(p, $0) }.min() ?? 0
                if d > bestDistance { bestDistance = d; best = p }
            }
            if bestDistance <= 1e-6 { break }
            centers.append(best)
        }
        var assignments = [Int](repeating: 0, count: points.count)
        for _ in 0..<iterations {
            var sums = [SIMD3<Double>](repeating: .zero, count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for (i, p) in points.enumerated() {
                var bestIndex = 0
                var bestDistance = Double.infinity
                for (j, c) in centers.enumerated() {
                    let d = simdDistanceSquared(p, c)
                    if d < bestDistance { bestDistance = d; bestIndex = j }
                }
                assignments[i] = bestIndex
                sums[bestIndex] += p
                counts[bestIndex] += 1
            }
            for j in centers.indices where counts[j] > 0 {
                centers[j] = sums[j] / Double(counts[j])
            }
        }
        var counts = [Int](repeating: 0, count: centers.count)
        for a in assignments { counts[a] += 1 }
        return zip(centers, counts).map { Cluster(center: $0, count: $1) }
    }

    private func simdDistanceSquared(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return (d * d).sum()
    }

    private func hueDistance(_ a: RGBAColor, _ b: RGBAColor) -> Double {
        let d = abs(a.hsb.hue - b.hsb.hue)
        return min(d, 1 - d)
    }
}
