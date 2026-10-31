import AfterglowCore
import AppKit
import QuartzCore

/// Four composited layers, each a conic gradient seen through its own mask:
/// wide outer glow → diffused glow → bright band → thin highlight.
///
/// The gradients carry the animator's light field (64 stops spaced evenly along the
/// edge). Masks are rebuilt only when geometry or shape-related style changes; per-frame
/// work is limited to colours and opacities.
@MainActor
public final class EdgeGlowView: NSView {
    private let root = CALayer()
    private let outer = CAGradientLayer()
    private let medium = CAGradientLayer()
    private let band = CAGradientLayer()
    private let highlight = CAGradientLayer()
    private let outerMask = CALayer()
    private let mediumMask = CALayer()
    private let bandMask = CALayer()
    private let highlightMask = CAShapeLayer()

    private struct MaskKey: Equatable {
        var geometry: GlowGeometry
        var thickness: Double
        var spread: Double
        var blur: Double
    }
    private var maskKey: MaskKey?
    private var hdrEnabled = false
    // Last colours sent to each layer; unchanged fields are not re-sent, because Core
    // Animation colour-converts every stop on assignment.
    private var lastFields: [ObjectIdentifier: [RGBAColor]] = [:]
    private var lastHeadroom = 1.0
    /// Stop counts per layer: blurred layers are smooth, so fewer stops look identical.
    private static let wideStops = 16
    private static let softStops = 32
    private let extendedSRGB = CGColorSpace(name: CGColorSpace.extendedSRGB)!

    public override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root
        wantsLayer = true
        root.masksToBounds = true

        for (gradient, mask) in [(outer, outerMask), (medium, mediumMask), (band, bandMask)] {
            setUp(gradient)
            mask.contentsGravity = .resize
            gradient.mask = mask
        }
        setUp(highlight)
        highlightMask.fillColor = nil
        highlightMask.strokeColor = CGColor(gray: 1, alpha: 1)
        highlightMask.lineJoin = .round
        highlight.mask = highlightMask
        [outer, medium, band, highlight].forEach(root.addSublayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func setUp(_ gradient: CAGradientLayer) {
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.opacity = 0
        gradient.actions = ["colors": NSNull(), "locations": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    /// - Parameter minimumMaskWidth: pixel floor for blurred masks, so small previews stay smooth.
    public func configure(geometry: GlowGeometry, style: GlowStyle, hdr: Bool = false, minimumMaskWidth: CGFloat = 220) {
        setHDR(hdr)
        let key = MaskKey(geometry: geometry, thickness: style.thickness, spread: style.spread, blur: style.blur)
        guard key != maskKey else { return }
        maskKey = key

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: geometry.size)
        for layer in [outer, medium, band, highlight, outerMask, mediumMask, bandMask, highlightMask] as [CALayer] {
            layer.frame = bounds
        }
        func locations(_ count: Int) -> [NSNumber] { geometry.conicLocations(count: count).map { NSNumber(value: $0) } }
        outer.locations = locations(Self.wideStops)
        medium.locations = locations(Self.softStops)
        band.locations = locations(GlowAnimator.fieldResolution)
        highlight.locations = locations(GlowAnimator.fieldResolution)
        lastFields.removeAll()

        func scale(_ base: CGFloat) -> CGFloat {
            max(base, min(1, minimumMaskWidth / max(geometry.size.width, 1)))
        }
        let thickness = CGFloat(style.thickness)
        let spread = CGFloat(style.spread)
        let softness = CGFloat(style.blur)
        outerMask.contents = GlowMaskRenderer.mask(
            geometry: geometry, inwardWidth: spread * 0.45,
            blur: spread * (0.3 + 0.45 * softness), scale: scale(0.125)
        )
        mediumMask.contents = GlowMaskRenderer.mask(
            geometry: geometry, inwardWidth: thickness + spread * 0.12,
            blur: spread * (0.1 + 0.15 * softness) + thickness, scale: scale(0.25)
        )
        bandMask.contents = GlowMaskRenderer.mask(
            geometry: geometry, inwardWidth: thickness,
            blur: thickness * (0.35 + softness) + 0.5, scale: scale(0.5)
        )
        highlightMask.path = geometry.path()
        highlightMask.lineWidth = 2 * max(0.75, thickness * 0.15)
        highlightMask.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    private func setHDR(_ enabled: Bool) {
        guard enabled != hdrEnabled else { return }
        hdrEnabled = enabled
        if #available(macOS 26, *) {
            highlight.preferredDynamicRange = enabled ? .high : .standard
        } else {
            highlight.wantsExtendedDynamicRangeContent = enabled
        }
    }

    public func apply(_ frame: GlowFrame) {
        guard !frame.field.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setColors(outer, Self.downsample(frame.wideField, to: Self.wideStops))
        setColors(medium, Self.downsample(frame.softField, to: Self.softStops))
        setColors(band, frame.field)
        let headroom = hdrEnabled ? max(1, frame.hdrHeadroom) : 1
        if headroom != lastHeadroom || lastFields[ObjectIdentifier(highlight)] != frame.highlightField {
            lastHeadroom = headroom
            lastFields[ObjectIdentifier(highlight)] = frame.highlightField
            highlight.colors = (frame.highlightField + [frame.highlightField[0]]).map { color(for: $0, headroom: headroom) }
        }
        outer.opacity = Float(frame.outerOpacity)
        medium.opacity = Float(frame.mediumOpacity)
        band.opacity = Float(frame.bandOpacity)
        highlight.opacity = Float(frame.highlightOpacity)
        CATransaction.commit()
    }

    private func setColors(_ layer: CAGradientLayer, _ field: [RGBAColor]) {
        let key = ObjectIdentifier(layer)
        guard lastFields[key] != field else { return }
        lastFields[key] = field
        layer.colors = (field + [field[0]]).map(\.cgColor)
    }

    /// Picks evenly spaced samples (inputs are already smoothed, so no filtering needed).
    static func downsample(_ field: [RGBAColor], to count: Int) -> [RGBAColor] {
        guard field.count > count, count > 0 else { return field }
        let step = Double(field.count) / Double(count)
        return (0..<count).map { field[Int(Double($0) * step)] }
    }

    /// Idle breathing as a Core Animation opacity animation on the root layer, so the
    /// frame loop can stop. `frame` should be the steady (unbreathed) idle frame.
    public func startBreathing() {
        guard root.animation(forKey: "breathe") == nil else { return }
        let low = GlowAnimator.breatheMid - GlowAnimator.breatheAmplitude
        let high = GlowAnimator.breatheMid + GlowAnimator.breatheAmplitude
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = low
        animation.toValue = high
        animation.duration = .pi / GlowAnimator.breatheRate
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = Float(GlowAnimator.breatheMid)
        root.add(animation, forKey: "breathe")
        CATransaction.commit()
    }

    public func stopBreathing() {
        guard root.animation(forKey: "breathe") != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.removeAnimation(forKey: "breathe")
        root.opacity = 1
        CATransaction.commit()
    }

    /// Colours brighter than SDR white on EDR displays; plain sRGB otherwise.
    private func color(for c: RGBAColor, headroom: Double) -> CGColor {
        guard headroom > 1 else { return c.cgColor }
        let r = c.red * headroom, g = c.green * headroom, b = c.blue * headroom
        if #available(macOS 26, *) {
            return CGColor(headroom: Float(headroom), colorSpace: extendedSRGB, red: r, green: g, blue: b, alpha: c.alpha)
                ?? c.cgColor
        }
        return CGColor(colorSpace: extendedSRGB, components: [r, g, b, c.alpha]) ?? c.cgColor
    }
}
