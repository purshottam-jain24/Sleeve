import AfterglowCore
import AppKit
import SwiftUI

/// Design tokens from docs/04-design-system.md.
enum DS {
    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
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

    enum Font {
        static let display = SwiftUI.Font.system(size: 34, weight: .bold)
        static let heroTitle = SwiftUI.Font.system(size: 30, weight: .bold)
        static let heroSubtitle = SwiftUI.Font.system(size: 18, weight: .medium)
        static let sectionTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let subtitle = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()
    }
}

extension RGBAColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }
}
