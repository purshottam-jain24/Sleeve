import SleeveAudio
import SleeveCore
import Foundation

/// Everything the glow needs to know for one frame.
public struct GlowInputs: Sendable {
    public var style: GlowStyle
    public var idleBehavior: GlowIdleBehavior
    /// Up to three target colours (artwork-derived or manual).
    public var colors: [RGBAColor]
    public var isPlaying: Bool
    public var audio: AudioFeatures
    public var reduceMotion: Bool
    public var hdr: Bool

    public init(
        style: GlowStyle,
        idleBehavior: GlowIdleBehavior,
        colors: [RGBAColor],
        isPlaying: Bool,
        audio: AudioFeatures = .silent,
        reduceMotion: Bool = false,
        hdr: Bool = false
    ) {
        self.style = style
        self.idleBehavior = idleBehavior
        self.colors = colors
        self.isPlaying = isPlaying
        self.audio = audio
        self.reduceMotion = reduceMotion
        self.hdr = hdr
    }
}

/// Per-frame values applied to the four glow layers.
public struct GlowFrame: Sendable, Equatable {
    public var outerOpacity: Double
    public var mediumOpacity: Double
    public var bandOpacity: Double
    public var highlightOpacity: Double
    /// Light colour at `fieldResolution` evenly spaced points around the display edge,
    /// starting at the middle of the right edge and running counter-clockwise.
    public var field: [RGBAColor]
    /// Spatially smoothed fields for the wide layers. Conic gradients turn sharp stops
    /// into wedges radiating from the centre, which the broad outer glow would expose as
    /// beams; diffused light should be soft anyway.
    public var softField: [RGBAColor]
    public var wideField: [RGBAColor]
    public var highlightField: [RGBAColor]
    /// Multiplier for highlight brightness on EDR displays (1 = SDR white).
    public var hdrHeadroom: Double
    /// `false` when nothing will change until the inputs do, so rendering can pause.
    public var needsContinuousUpdates: Bool
    /// Fully idle (nothing playing or audible) with colours settled. The renderer can then
    /// hand idle breathing to Core Animation and stop its frame loop.
    public var isSettledIdle: Bool
}

/// Turns settings + audio + time into a `GlowFrame`.
///
/// The glow is modelled as a light *field* sampled around the perimeter: each preset
/// defines colour and brightness as a function of edge position `s` (0..<1) and time.
/// Pure apart from its own smoothing state, so it is unit-tested without windows.
public struct GlowAnimator: Sendable {
    public static let fieldResolution = 64
    /// Idle breathing: opacity factor = mid + amplitude·sin(rate·t). Shared with the Core
    /// Animation version so handing over is seamless.
    public static let breatheMid = 0.38
    public static let breatheAmplitude = 0.17
    public static let breatheRate = 0.7

    private var time: Double = 0
    private var phase: Double = 0
    private var cometHead: Double = 0
    /// Tide: how far up the sides the colour reaches (0 = bottom only, 1 = all round).
    private var tideLevel: Double = 0.3
    private var activeness: Double = 0
    private var colors: [RGBAColor] = []
    private var hasFrame = false

    public init() {}

    public mutating func next(_ inputs: GlowInputs, dt rawDt: Double) -> GlowFrame {
        let dt = min(max(rawDt, 0), 0.1)
        let style = inputs.style
        let speed = style.animationSpeed
        let audio = inputs.audio
        let motion = !inputs.reduceMotion
        time += dt

        // Palette transition (~1.2 s to settle).
        let targets = Self.normalizedColors(inputs.colors)
        if !hasFrame || colors.count != targets.count {
            colors = targets
        } else {
            let t = 1 - exp(-dt / 0.35)
            colors = zip(colors, targets).map { $0.interpolated(to: $1, fraction: t) }
        }
        let colorsSettled = zip(colors, targets).allSatisfy { a, b in
            abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue) < 0.004
        }

        // Blend smoothly between the active look and the idle behaviour.
        let audible = !audio.isSilent && audio.level > 0.02
        let targetActive: Double = (inputs.isPlaying || audible) ? 1 : 0
        activeness += (targetActive - activeness) * (1 - exp(-dt / 0.6))
        if abs(activeness - targetActive) < 0.002 { activeness = targetActive }
        hasFrame = true

        let beat = style.beatSync ? Double(audio.beat) : 0
        let level = Double(audio.level), bass = Double(audio.bass)
        let mid = Double(audio.mid), treble = Double(audio.treble)

        // Layer opacities and motion per preset.
        var outer = 1.0, medium = 1.0, band = 1.0, highlight = 1.0
        var phaseRate = 0.0
        var continuous = true
        switch style.preset {
        case .ambient:
            continuous = false
        case .musicSync:
            let energy = 0.25 + 0.75 * level
            outer = 0.35 + 0.75 * bass + 0.25 * beat
            medium = 0.4 + 0.6 * energy
            band = 0.5 + 0.5 * energy + 0.2 * beat
            highlight = 0.4 + 0.6 * treble
        case .flow:
            phaseRate = speed * (0.04 + 0.09 * level)
            outer = 0.7 + 0.3 * bass + 0.15 * beat
            medium = 0.75 + 0.25 * level
            band = 0.8 + 0.2 * level
        case .pulse:
            let breath = motion ? 0.5 + 0.5 * sin(time * speed * 1.4) : 0.5
            outer = 0.45 + 0.45 * breath + 0.45 * beat + 0.2 * bass
            medium = 0.55 + 0.35 * breath + 0.3 * beat
            band = 0.7 + 0.2 * breath + 0.2 * beat
            highlight = 0.6 + 0.4 * breath
        case .spectrum:
            outer = 0.55 + 0.45 * bass + 0.15 * beat
            medium = 0.7 + 0.3 * mid
            band = 0.95
            highlight = 0.5 + 0.5 * treble
        case .cinematic:
            phaseRate = speed * 0.015
            let breath = motion ? 0.88 + 0.12 * sin(time * speed * 0.4) : 1
            outer = breath * (0.75 + 0.3 * bass) + 0.08 * beat
            medium = breath * (0.8 + 0.2 * mid)
            band = 0.85 + 0.15 * level
            highlight = 0.7
        case .aurora:
            phaseRate = speed * 0.02
            outer = 0.8 + 0.3 * bass + 0.1 * beat
            medium = 0.85 + 0.15 * mid
            band = 0.9
            highlight = 0.55 + 0.35 * treble
        case .comet:
            outer = 0.5 + 0.35 * bass + 0.2 * beat
            medium = 0.7
            band = 1
            highlight = 1
        case .halo:
            outer = 0.6 + 0.6 * bass + 0.2 * beat
            medium = 0.7 + 0.3 * bass
            band = 0.8 + 0.2 * level
            highlight = 0.5 + 0.4 * treble
        case .tide:
            phaseRate = speed * 0.01
            outer = 0.7 + 0.3 * bass
            medium = 0.85
            band = 0.95
            highlight = 0.55
            // Rises quickly with loudness, ebbs slowly.
            let target = 0.15 + 0.85 * min(1, level * 1.25 + 0.3 * beat)
            let tau = target > tideLevel ? 0.25 : 1.6
            tideLevel += (target - tideLevel) * (1 - exp(-dt / tau))
        case .prism:
            phaseRate = speed * (0.03 + 0.05 * mid)
            outer = 0.65 + 0.3 * bass
            medium = 0.8 + 0.2 * mid
            band = 0.9
            highlight = 0.5 + 0.6 * treble
        case .ember:
            outer = 0.45 + 0.35 * bass + 0.25 * beat
            medium = 0.6 + 0.25 * mid
            band = 0.75 + 0.25 * level
            highlight = 0.45 + 0.35 * beat
        case .studio:
            continuous = false
            outer = 0.9
            medium = 0.9
            band = 0.85
            highlight = 0.5
        }
        if !motion { phaseRate = 0 }
        phase = (phase + phaseRate * dt * activeness).truncatingRemainder(dividingBy: 1)
        if style.preset == .comet, motion {
            let rate = speed * (0.11 + 0.22 * level + 0.7 * beat)
            cometHead = (cometHead + rate * dt * max(activeness, 0.15)).truncatingRemainder(dividingBy: 1)
        }

        // Idle look.
        let idleFactor: Double = switch inputs.idleBehavior {
        case .breathe: motion ? Self.breatheMid + Self.breatheAmplitude * sin(time * Self.breatheRate) : 0.45
        case .dim: 0.3
        case .steady: 1
        case .hide: 0
        }
        if inputs.idleBehavior == .breathe && activeness < 1 { continuous = true }
        if (style.preset == .ambient || style.preset == .studio) && inputs.isPlaying { continuous = false }

        func blend(_ active: Double, resting: Double) -> Double {
            activeness * active + (1 - activeness) * resting * idleFactor
        }
        let intensity = style.intensity
        let frameOuter = Self.clamp(blend(outer, resting: 0.8) * 0.55 * intensity)
        let frameMedium = Self.clamp(blend(medium, resting: 0.85) * 0.7 * intensity)
        let frameBand = Self.clamp(blend(band, resting: 0.9) * 0.9 * intensity)
        let frameHighlight = Self.clamp(blend(highlight, resting: 0.8) * 0.6 * intensity)

        // Light field.
        let n = Self.fieldResolution
        let angleOffset = style.gradientAngle / 360
        var field = [RGBAColor]()
        var highlightField = [RGBAColor]()
        field.reserveCapacity(n)
        highlightField.reserveCapacity(n)
        let t = motion ? time * speed : 0
        for i in 0..<n {
            let s = Double(i) / Double(n)
            let (color, brightness, whiteness) = sample(
                preset: style.preset, s: s, t: t, angleOffset: angleOffset,
                audio: audio, level: level, bass: bass, mid: mid, treble: treble, beat: beat
            )
            let b = activeness * brightness + (1 - activeness)
            let w = activeness * whiteness
            let lit = Self.light(color, brightness: b, whiteness: w)
            field.append(lit)
            highlightField.append(lit.interpolated(to: .white, fraction: 0.5 + 0.3 * w))
        }

        let headroom = inputs.hdr ? 1 + activeness * (0.35 + 0.65 * beat + 0.3 * treble) : 1

        let settled = colorsSettled && (activeness == 0 || activeness == 1)
        let hidden = frameOuter + frameMedium + frameBand + frameHighlight < 0.001
        // Motion only advances while active; when idle, only breathing changes anything.
        let breathing = inputs.idleBehavior == .breathe && motion && activeness < 1
        let needsUpdates = !settled || hidden == false && ((activeness > 0 && continuous) || breathing)

        return GlowFrame(
            outerOpacity: frameOuter,
            mediumOpacity: frameMedium,
            bandOpacity: frameBand,
            highlightOpacity: frameHighlight,
            field: field,
            softField: Self.circularBlur(field, sigma: 1.6),
            wideField: Self.circularBlur(field, sigma: 3.5),
            highlightField: highlightField,
            hdrHeadroom: headroom,
            needsContinuousUpdates: needsUpdates,
            isSettledIdle: colorsSettled && activeness == 0
        )
    }

    // MARK: Field sampling

    /// - Returns: base colour, brightness multiplier (≈0.1...1.4) and how far to push
    ///   towards white (for comet heads and hot spots).
    private func sample(
        preset: GlowPreset, s: Double, t: Double, angleOffset: Double,
        audio: AudioFeatures, level: Double, bass: Double, mid: Double, treble: Double, beat: Double
    ) -> (RGBAColor, Double, Double) {
        let twoPi = 2 * Double.pi
        switch preset {
        case .ambient, .pulse:
            return (cyclic(s + angleOffset), 1, 0)
        case .musicSync:
            return (cyclic(s + angleOffset), 0.55 + 0.45 * level + 0.25 * beat, 0.15 * beat)
        case .flow:
            let shimmer = 0.1 * sin(twoPi * (2 * s - t * 0.25))
            return (cyclic(s + angleOffset + phase), 0.88 + 0.12 * level + shimmer, 0)
        case .spectrum:
            // Distance from the bottom centre (s = 0.75): bass there, treble at the top.
            let d = Self.circularDistance(s, 0.75 + angleOffset) / 0.5
            let value = pow(Self.spectrumValue(audio, at: d, bass: bass, mid: mid, treble: treble), 1.35)
            return (ramp(d), 0.06 + 1.45 * value, max(0, value - 0.75) * 1.6)
        case .cinematic:
            let wave = 0.5 + 0.5 * sin(twoPi * 2 * s + t * 0.35)
            return (cyclic(s + angleOffset + phase), 0.74 + 0.22 * wave + 0.15 * bass, 0)
        case .aurora:
            let w1 = 0.5 + 0.5 * sin(twoPi * 3 * s + t * 0.6)
            let w2 = 0.5 + 0.5 * sin(twoPi * 5 * s - t * 0.9 + 1.3)
            let ribbons = pow(max(w1, w2), 2.2)
            let shift = 0.18 * w2
            return (cyclic(s + angleOffset + phase + shift), 0.28 + ribbons * (0.75 + 0.45 * mid), 0.2 * ribbons * treble)
        case .comet:
            var glow = 0.0, head = 0.0
            for h in [cometHead, cometHead + 0.5] {
                let behind = Self.wrap(h - s)       // tail trails behind the head
                let ahead = Self.wrap(s - h)
                glow = max(glow, exp(-behind / 0.11), exp(-ahead / 0.012))
                head = max(head, exp(-min(behind, ahead) / 0.015))
            }
            return (cyclic(s + angleOffset), 0.12 + 1.2 * glow, 0.55 * head)
        case .halo:
            // Corners of a ~16:10 display, measured along the perimeter from mid-right.
            var corner = 0.0
            for c in [0.096, 0.404, 0.596, 0.904] {
                corner = max(corner, exp(-Self.circularDistance(s, c) / (0.05 + 0.05 * bass)))
            }
            return (cyclic(s + angleOffset), 0.08 + (0.95 + 0.45 * bass) * corner, 0.25 * corner * beat)
        case .tide:
            // Height above the bottom centre, 0 (bottom) ... 1 (top centre).
            let d = Self.circularDistance(s, 0.75 + angleOffset) / 0.5
            let edge = 0.06
            let water = 1 - Self.smoothstep(min(max((d - tideLevel) / edge + 0.5, 0), 1))
            let swell = 0.06 * sin(twoPi * 6 * s + t * 1.1)
            return (ramp(d * 0.8 + phase), 0.1 + 1.0 * water + swell * water, 0.3 * water * max(0, 1 - abs(d - tideLevel) / edge) * level)
        case .prism:
            // Three copies of the palette drifting at different speeds; where they agree,
            // the light runs hot.
            let a = 0.5 + 0.5 * sin(twoPi * (2 * s + phase))
            let b = 0.5 + 0.5 * sin(twoPi * (3 * s - phase * 1.3) + 2.1)
            let c = 0.5 + 0.5 * sin(twoPi * (5 * s + phase * 0.7) + 4.2)
            let bands = (a * b + b * c + a * c) / 3
            let color = cyclic(s + angleOffset + 0.15 * (a - c))
            return (color, 0.3 + 1.1 * bands, pow(bands, 3) * (0.3 + 1.2 * treble))
        case .ember:
            // Layered value noise flickers; beats kick a few bright sparks.
            let flicker = 0.55 * Self.noise(s * 14 + t * 0.9) + 0.3 * Self.noise(s * 37 - t * 1.7) + 0.15 * Self.noise(s * 71 + t * 3.1)
            let spark = pow(max(0, Self.noise(s * 23 + floor(t * 2) * 7.3) - 0.62) / 0.38, 2) * beat
            let warm = ramp(0.15 + 0.5 * flicker).interpolated(to: RGBAColor(red: 1, green: 0.55, blue: 0.2), fraction: 0.35)
            return (warm, 0.25 + 0.75 * flicker * (0.6 + 0.6 * mid) + 1.1 * spark, 0.6 * spark)
        case .studio:
            // Top half: neutral daylight; bottom half: the palette, softly.
            let top = Self.smoothstep(min(max(1 - Self.circularDistance(s, 0.25) / 0.32, 0), 1))
            let neutral = RGBAColor(red: 1, green: 0.97, blue: 0.93)
            return (cyclic(s + angleOffset).interpolated(to: neutral, fraction: top), 0.55 + 0.4 * top, 0.15 * top)
        }
    }

    /// Smooth 1-D value noise in 0...1 (deterministic, no state).
    static func noise(_ x: Double) -> Double {
        let i = floor(x), f = x - i
        func hash(_ n: Double) -> Double {
            let v = sin(n * 127.1 + 311.7) * 43758.5453
            return v - floor(v)
        }
        return hash(i) + (hash(i + 1) - hash(i)) * smoothstep(f)
    }

    /// Palette repeated around the edge with smooth transitions.
    private func cyclic(_ position: Double) -> RGBAColor {
        let x = Self.wrap(position) * Double(colors.count)
        let i = Int(x) % colors.count
        let f = Self.smoothstep(x - floor(x))
        return colors[i].interpolated(to: colors[(i + 1) % colors.count], fraction: f)
    }

    /// Palette as a ramp 0...1 (primary → secondary → tertiary).
    private func ramp(_ d: Double) -> RGBAColor {
        let x = min(max(d, 0), 1) * Double(colors.count - 1)
        let i = min(Int(x), colors.count - 2)
        return colors[i].interpolated(to: colors[i + 1], fraction: Self.smoothstep(x - Double(i)))
    }

    static func spectrumValue(_ audio: AudioFeatures, at d: Double, bass: Double, mid: Double, treble: Double) -> Double {
        let bands = audio.spectrum
        guard bands.count > 1 else {
            return d < 0.5 ? bass + (mid - bass) * d * 2 : mid + (treble - mid) * (d - 0.5) * 2
        }
        let x = min(max(d, 0), 1) * Double(bands.count - 1)
        let i = min(Int(x), bands.count - 2)
        let f = x - Double(i)
        return Double(bands[i]) * (1 - f) + Double(bands[i + 1]) * f
    }

    // MARK: Helpers

    static func light(_ color: RGBAColor, brightness: Double, whiteness: Double) -> RGBAColor {
        let k = max(0, brightness)
        let scaled = RGBAColor(
            red: min(1, color.red * min(k, 1)),
            green: min(1, color.green * min(k, 1)),
            blue: min(1, color.blue * min(k, 1))
        )
        // Brightness above 1 and explicit whiteness both push towards white-hot.
        let push = min(1, max(0, k - 1) * 0.6 + whiteness)
        return scaled.interpolated(to: .white, fraction: push)
    }

    static func normalizedColors(_ input: [RGBAColor]) -> [RGBAColor] {
        switch input.count {
        case 0: return ArtworkPalette.fallback.glowColors
        case 1: return [input[0], input[0].scaledBrightness(0.75), input[0]]
        case 2: return [input[0], input[1], input[0].interpolated(to: input[1], fraction: 0.5)]
        default: return Array(input.prefix(3))
        }
    }

    static func wrap(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }

    static func circularDistance(_ a: Double, _ b: Double) -> Double {
        let d = wrap(a - b)
        return min(d, 1 - d)
    }

    static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// Gaussian blur around the closed perimeter (indices wrap).
    static func circularBlur(_ field: [RGBAColor], sigma: Double) -> [RGBAColor] {
        let n = field.count
        let radius = Int((sigma * 2.5).rounded(.up))
        guard n > 0, radius > 0 else { return field }
        let weights = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = weights.reduce(0, +)
        return (0..<n).map { i in
            var r = 0.0, g = 0.0, b = 0.0
            for (k, w) in weights.enumerated() {
                let c = field[((i + k - radius) % n + n) % n]
                r += c.red * w; g += c.green * w; b += c.blue * w
            }
            return RGBAColor(red: r / total, green: g / total, blue: b / total)
        }
    }

    static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
