import CoreGraphics
import Foundation
import Testing
@testable import AfterglowGlow

struct GlowMaskRendererTests {
    /// Regression: an A8/nil-colour-space render silently returned nil, so only the
    /// highlight layer was ever visible. Masks are now 16-bit to avoid banding.
    @Test func maskIsBrightAtEdgeAndFadesInward() throws {
        let geometry = GlowGeometry(size: CGSize(width: 1512, height: 982), cornerRadius: 10, notch: nil, notchMode: .ignore)
        let mask = try #require(GlowMaskRenderer.mask(geometry: geometry, inwardWidth: 60, blur: 60, scale: 0.25))
        #expect(mask.width == 378 && mask.height == 246)

        // Redraw into a known 8-bit RGBA layout so the test doesn't depend on the mask's storage format.
        let ctx = try #require(CGContext(
            data: nil, width: mask.width, height: mask.height, bitsPerComponent: 8, bytesPerRow: mask.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
        let pixels = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        func alpha(x: Int, y: Int) -> UInt8 { pixels[y * mask.width * 4 + x * 4 + 3] }

        let midY = mask.height / 2
        #expect(alpha(x: 0, y: midY) > 180)
        #expect(alpha(x: 10, y: midY) < alpha(x: 0, y: midY))
        #expect(alpha(x: mask.width / 2, y: midY) < 8)
    }
}
