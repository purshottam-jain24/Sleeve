import CoreGraphics
import Testing
@testable import AfterglowCore

struct ArtworkColorExtractorTests {
    func image(_ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }

    func hue(_ c: RGBAColor) -> Double { c.hsb.hue }

    @Test func findsTwoDominantHues() throws {
        let img = image { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 64))
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1))
            ctx.fill(CGRect(x: 40, y: 0, width: 24, height: 64))
        }
        let palette = try #require(ArtworkColorExtractor().palette(from: img))
        #expect(!palette.isMonochrome)
        let hues = [hue(palette.primary), hue(palette.secondary)]
        #expect(hues.contains { $0 < 0.03 || $0 > 0.97 }) // red
        #expect(hues.contains { abs($0 - 0.64) < 0.05 })   // blue
    }

    @Test func greyscaleArtworkIsMonochrome() throws {
        let img = image { ctx in
            ctx.setFillColor(CGColor(gray: 0.3, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            ctx.setFillColor(CGColor(gray: 0.8, alpha: 1)); ctx.fill(CGRect(x: 0, y: 32, width: 64, height: 32))
        }
        let palette = try #require(ArtworkColorExtractor().palette(from: img))
        #expect(palette.isMonochrome)
        #expect(palette.glowColors.allSatisfy { $0.hsb.saturation <= 0.16 })
    }

    @Test func glowColorsAreBright() {
        #expect(ArtworkPalette.fallback.glowColors.allSatisfy { $0.hsb.brightness >= 0.9 })
    }

    @Test func rgbHsbRoundTrip() {
        let c = RGBAColor(red: 0.2, green: 0.6, blue: 0.4)
        let (h, s, b) = c.hsb
        let back = RGBAColor(hue: h, saturation: s, brightness: b)
        #expect(abs(back.red - c.red) < 1e-9 && abs(back.green - c.green) < 1e-9 && abs(back.blue - c.blue) < 1e-9)
    }
}
