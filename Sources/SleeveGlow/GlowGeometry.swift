import SleeveCore
import CoreGraphics

/// Describes one display's drawable area for the glow, in the overlay's local
/// coordinates (origin bottom-left, points).
public struct GlowGeometry: Sendable, Equatable {
    public var size: CGSize
    public var cornerRadius: CGFloat
    /// The notch rectangle, if the display has one.
    public var notch: CGRect?
    public var notchMode: NotchMode

    public init(size: CGSize, cornerRadius: CGFloat, notch: CGRect?, notchMode: NotchMode) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.notch = notch
        self.notchMode = notchMode
    }

    /// Perimeter path along the display edge, optionally following or skipping the notch.
    public func path(scale: CGFloat = 1) -> CGPath {
        let w = size.width * scale
        let h = size.height * scale
        let r = min(cornerRadius * scale, min(w, h) / 2)
        let path = CGMutablePath()

        guard let notch, notchMode != .ignore, notch.width > 0 else {
            path.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: r, cornerHeight: r)
            return path
        }

        let nMinX = notch.minX * scale
        let nMaxX = notch.maxX * scale
        let nBottom = h - notch.height * scale
        let nr = min(8 * scale, notch.width * scale / 4, notch.height * scale / 2)

        // Start just right of the notch on the top edge and travel clockwise.
        path.move(to: CGPoint(x: nMaxX, y: h))
        path.addLine(to: CGPoint(x: w - r, y: h))
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w, y: h - r), radius: r)
        path.addLine(to: CGPoint(x: w, y: r))
        path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w - r, y: 0), radius: r)
        path.addLine(to: CGPoint(x: r, y: 0))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: 0, y: r), radius: r)
        path.addLine(to: CGPoint(x: 0, y: h - r))
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: r, y: h), radius: r)
        path.addLine(to: CGPoint(x: nMinX, y: h))

        if notchMode == .wrap {
            path.addArc(tangent1End: CGPoint(x: nMinX, y: nBottom), tangent2End: CGPoint(x: nMinX + nr, y: nBottom), radius: nr)
            path.addArc(tangent1End: CGPoint(x: nMaxX, y: nBottom), tangent2End: CGPoint(x: nMaxX, y: nBottom + nr), radius: nr)
            path.addLine(to: CGPoint(x: nMaxX, y: h))
            path.closeSubpath()
        }
        // `.gap` leaves the path open across the notch.
        return path
    }

    /// Conic-gradient stop locations for `count` points spaced evenly by *edge length*,
    /// starting at the middle of the right edge and running counter-clockwise, plus a
    /// closing stop at 1.
    ///
    /// `CAGradientLayer` measures conic angles in the layer's unit square, so on a wide
    /// display equal angles would bunch stops along the short edges; this undoes that.
    public func conicLocations(count: Int) -> [Double] {
        let w = max(size.width, 1), h = max(size.height, 1)
        let perimeter = 2 * (w + h)
        var locations: [Double] = []
        locations.reserveCapacity(count + 1)
        for i in 0..<count {
            var d = Double(i) / Double(count) * perimeter
            let point: CGPoint
            if d < h / 2 {
                point = CGPoint(x: w, y: h / 2 + d)
            } else if (d - h / 2) < w {
                d -= h / 2
                point = CGPoint(x: w - d, y: h)
            } else if (d - h / 2 - w) < h {
                d -= h / 2 + w
                point = CGPoint(x: 0, y: h - d)
            } else if (d - h / 2 - w - h) < w {
                d -= h / 2 + w + h
                point = CGPoint(x: d, y: 0)
            } else {
                d -= h / 2 + 2 * w + h
                point = CGPoint(x: w, y: d)
            }
            var angle = atan2(point.y / h - 0.5, point.x / w - 0.5)
            if angle < 0 { angle += 2 * .pi }
            // Guard monotonicity against floating-point noise at the start.
            let location = i == 0 ? 0 : max(angle / (2 * .pi), locations.last ?? 0)
            locations.append(location)
        }
        locations.append(1)
        return locations
    }
}
