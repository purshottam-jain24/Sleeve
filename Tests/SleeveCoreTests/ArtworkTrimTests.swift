import CoreGraphics
import Foundation
import Testing
@testable import SleeveCore

struct ArtworkTrimTests {
    /// `content` is drawn with per-pixel noise so it never looks like a flat bar.
    private func image(width: Int, height: Int, background: (Double, Double, Double), content: CGRect) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: background.0, green: background.1, blue: background.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var seed: UInt64 = 42
        for x in stride(from: Int(content.minX), to: Int(content.maxX), by: 4) {
            for y in stride(from: Int(content.minY), to: Int(content.maxY), by: 4) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let v = Double(seed >> 56) / 255
                ctx.setFillColor(CGColor(srgbRed: v, green: 1 - v, blue: 0.5, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        return ctx.makeImage()!
    }

    @Test func trimsSideBarsAroundASquareCover() throws {
        // 1280×720 with a 720×720 cover in the middle and brown bars (YouTube Art Track).
        let img = image(width: 1280, height: 720, background: (0.32, 0.14, 0.14), content: CGRect(x: 280, y: 0, width: 720, height: 720))
        let rect = try #require(ArtworkTrim.contentRect(of: img))
        #expect(abs(rect.width - 720) < 30)
        #expect(abs(rect.midX - 640) < 10)
        #expect(rect.height == 720)
    }

    @Test func trimsLetterboxAboveAndBelow() throws {
        let img = image(width: 480, height: 360, background: (0, 0, 0), content: CGRect(x: 0, y: 45, width: 480, height: 270))
        let rect = try #require(ArtworkTrim.contentRect(of: img))
        #expect(abs(rect.height - 270) < 12)
        #expect(rect.width == 480)
    }

    @Test func leavesOrdinaryArtworkAlone() {
        let full = image(width: 600, height: 600, background: (0, 0, 0), content: CGRect(x: 0, y: 0, width: 600, height: 600))
        #expect(ArtworkTrim.contentRect(of: full) == nil)
        // A flat area on one side only (part of the design) isn't a bar.
        let oneSide = image(width: 1280, height: 720, background: (0.9, 0.9, 0.9), content: CGRect(x: 300, y: 0, width: 980, height: 720))
        #expect(ArtworkTrim.contentRect(of: oneSide) == nil)
        // Entirely flat: nothing sensible to keep.
        let flat = image(width: 400, height: 400, background: (0.2, 0.2, 0.2), content: .zero)
        #expect(ArtworkTrim.contentRect(of: flat) == nil)
    }
}
