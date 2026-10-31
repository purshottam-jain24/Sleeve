// Renders the Sleeve app icon (1024×1024 PNG): a record sliding out of a glowing album
// sleeve on a dark squircle. Run via scripts/make-icon.sh, which builds the .icns from it.
import AppKit
import CoreImage

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let full = CGRect(x: 0, y: 0, width: size, height: size)

func context() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func blurred(_ image: CGImage, _ radius: Double) -> CGImage {
    let input = CIImage(cgImage: image)
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    return CIContext().createCGImage(output, from: input.extent)!
}

let amber = color(0xFFA25C), rose = color(0xEC4A86), violet = color(0x6E44FF)
let squircle = CGRect(x: 100, y: 100, width: 824, height: 824)
let squirclePath = CGPath(roundedRect: squircle, cornerWidth: 186, cornerHeight: 186, transform: nil)
let sleeve = CGRect(x: 214, y: 298, width: 428, height: 428)
let sleevePath = CGPath(roundedRect: sleeve, cornerWidth: 30, cornerHeight: 30, transform: nil)
let recordCenter = CGPoint(x: 628, y: sleeve.midY)
let recordRadius: CGFloat = 200

/// The sleeve's cover: the brand gradient, used for the sleeve itself and its glow.
func sleeveArt() -> CGImage {
    let ctx = context()
    ctx.addPath(sleevePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [amber, rose, violet] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: sleeve.minX, y: sleeve.maxY), end: CGPoint(x: sleeve.maxX, y: sleeve.minY), options: [])
    return ctx.makeImage()!
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

let ctx = context()

// Squircle base with a soft drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.45))
ctx.addPath(squirclePath)
ctx.setFillColor(color(0x0B0914))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()
let base = CGGradient(colorsSpace: space, colors: [color(0x1E1430), color(0x07060B)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 512, y: squircle.maxY), end: CGPoint(x: 512, y: squircle.minY), options: [])

// Light from the cover spilling onto the background.
let art = sleeveArt()
ctx.setAlpha(0.6); ctx.draw(blurred(art, 90), in: full)
ctx.setAlpha(1)

// The record, half out of the sleeve.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.55))
ctx.addEllipse(in: circle(recordCenter, recordRadius))
ctx.setFillColor(color(0x0E0D12))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: circle(recordCenter, recordRadius))
ctx.clip()
let vinyl = CGGradient(colorsSpace: space, colors: [color(0x1A1820), color(0x0A090D)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(vinyl, startCenter: recordCenter, startRadius: 0, endCenter: recordCenter, endRadius: recordRadius, options: [])
// Grooves.
ctx.setLineWidth(1.5)
var r: CGFloat = 92
while r < recordRadius - 8 {
    ctx.setStrokeColor(color(0xFFFFFF, r.truncatingRemainder(dividingBy: 28) < 14 ? 0.07 : 0.035))
    ctx.strokeEllipse(in: circle(recordCenter, r))
    r += 9
}
// A diagonal sheen across the grooves.
let sheenBand = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0), color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray, locations: [0.3, 0.5, 0.7])!
ctx.drawLinearGradient(sheenBand, start: CGPoint(x: recordCenter.x - recordRadius, y: recordCenter.y + recordRadius),
                       end: CGPoint(x: recordCenter.x + recordRadius, y: recordCenter.y - recordRadius), options: [])
ctx.restoreGState()
// Label and spindle hole.
ctx.saveGState()
ctx.addEllipse(in: circle(recordCenter, 64))
ctx.clip()
let label = CGGradient(colorsSpace: space, colors: [color(0xFFC08A), amber] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(label, start: CGPoint(x: recordCenter.x, y: recordCenter.y + 64), end: CGPoint(x: recordCenter.x, y: recordCenter.y - 64), options: [])
ctx.restoreGState()
ctx.addEllipse(in: circle(recordCenter, 9))
ctx.setFillColor(color(0x0B0914))
ctx.fillPath()

// The sleeve, in front, casting a shadow onto the record.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 14, height: -8), blur: 34, color: color(0x000000, 0.6))
ctx.addPath(sleevePath)
ctx.setFillColor(color(0x000000))
ctx.fillPath()
ctx.restoreGState()
ctx.draw(art, in: full)
ctx.saveGState()
ctx.addPath(sleevePath)
ctx.clip()
// Soft highlight from the top-left, and a faint inner frame like printed card.
let gloss = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: sleeve.minX + 90, y: sleeve.maxY - 80), startRadius: 0,
                       endCenter: CGPoint(x: sleeve.minX + 90, y: sleeve.maxY - 80), endRadius: 340, options: [])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: sleeve.insetBy(dx: 1, dy: 1), cornerWidth: 29, cornerHeight: 29, transform: nil))
ctx.setLineWidth(2)
ctx.setStrokeColor(color(0xFFFFFF, 0.3))
ctx.strokePath()

// Top sheen and hairline edge, like system icons.
let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.08), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: squircle.maxY), end: CGPoint(x: 512, y: squircle.midY), options: [])
ctx.restoreGState()
ctx.addPath(squirclePath)
ctx.setLineWidth(2)
ctx.setStrokeColor(color(0xFFFFFF, 0.12))
ctx.strokePath()

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
