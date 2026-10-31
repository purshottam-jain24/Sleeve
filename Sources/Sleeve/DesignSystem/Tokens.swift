import SleeveCore
import AppKit
import SwiftUI

/// Design tokens from docs/04-design-system.md.
enum DS {
    enum Radius {
        static let xs: CGFloat = 5
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 22
        /// Content cards. Inner elements use `md`/`sm` so the curves stay concentric.
        static let card: CGFloat = 18
    }

    /// Neutral, warm near-black UI. Colour comes from the artwork, not the chrome; the one
    /// accent is a soft amber.
    enum Palette {
        static let base = Color(red: 0.055, green: 0.051, blue: 0.049)
        static let surface = Color.white.opacity(0.035)
        static let surfaceHover = Color.white.opacity(0.06)
        static let hairline = Color.white.opacity(0.075)
        static let separator = Color.white.opacity(0.06)
        static let textPrimary = Color.white.opacity(0.94)
        static let textSecondary = Color.white.opacity(0.6)
        static let textTertiary = Color.white.opacity(0.38)
        static let accent = Color(red: 0.97, green: 0.66, blue: 0.42)
        /// Card body: lit from above, so it's a touch lighter at the top.
        static let cardTop = Color.white.opacity(0.062)
        static let cardBottom = Color.white.opacity(0.03)
        /// Opaque under-layer so cards read the same over any backdrop colour.
        static let cardBase = Color(red: 0.07, green: 0.066, blue: 0.064).opacity(0.72)
        /// Recessed areas inside a card (lists, previews).
        static let inset = Color.black.opacity(0.22)
    }

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
    }

    enum Motion {
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
        static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.9)
        static let artwork = Animation.easeInOut(duration: 0.6)
        static let lyric = Animation.spring(response: 0.55, dampingFraction: 0.86)
    }

    /// Pair large sizes with negative tracking (`Tracking`), as SF Pro Display expects.
    enum Font {
        static let display = SwiftUI.Font.system(size: 34, weight: .semibold)
        static let pageTitle = SwiftUI.Font.system(size: 28, weight: .semibold)
        static let cardTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let heroTitle = SwiftUI.Font.system(size: 28, weight: .semibold)
        static let heroSubtitle = SwiftUI.Font.system(size: 17, weight: .regular)
        static let sectionTitle = SwiftUI.Font.system(size: 12, weight: .semibold)
        static let title = SwiftUI.Font.system(size: 13, weight: .medium)
        static let subtitle = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
    }

    enum Tracking {
        static let display: CGFloat = -0.9
        static let pageTitle: CGFloat = -0.6
        static let heroTitle: CGFloat = -0.6
        static let sectionTitle: CGFloat = 0.2
    }
}

extension RGBAColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }
}
