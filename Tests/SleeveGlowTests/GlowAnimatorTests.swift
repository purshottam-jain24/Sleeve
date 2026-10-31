import AfterglowAudio
import AfterglowCore
import CoreGraphics
import Testing
@testable import AfterglowGlow

struct GlowAnimatorTests {
    func inputs(_ preset: GlowPreset, playing: Bool = true, idle: GlowIdleBehavior = .breathe, audio: AudioFeatures = .silent) -> GlowInputs {
        var style = GlowStyle()
        style.preset = preset
        return GlowInputs(style: style, idleBehavior: idle, colors: ArtworkPalette.fallback.glowColors, isPlaying: playing, audio: audio)
    }

    func run(_ animator: inout GlowAnimator, _ inputs: GlowInputs, seconds: Double) -> GlowFrame {
        var frame: GlowFrame!
        for _ in 0..<Int(seconds * 60) { frame = animator.next(inputs, dt: 1.0 / 60) }
        return frame
    }

    func loud(bass: Float) -> AudioFeatures {
        AudioFeatures(level: 0.8, bass: bass, mid: 0.5, treble: 0.5, beat: 0, spectrum: [], isSilent: false)
    }

    @Test func ambientSettlesAndStopsRendering() {
        var a = GlowAnimator()
        let frame = run(&a, inputs(.ambient), seconds: 8)
        #expect(!frame.needsContinuousUpdates)
        #expect(frame.bandOpacity > 0)
    }

    @Test func hideIdleFadesOutCompletelyAndStops() {
        var a = GlowAnimator()
        let frame = run(&a, inputs(.cinematic, playing: false, idle: .hide), seconds: 8)
        #expect(frame.outerOpacity == 0 && frame.bandOpacity == 0)
        #expect(!frame.needsContinuousUpdates)
    }

    @Test func musicSyncFollowsBass() {
        var quiet = GlowAnimator(), heavy = GlowAnimator()
        let low = run(&quiet, inputs(.musicSync, audio: loud(bass: 0.1)), seconds: 3)
        let high = run(&heavy, inputs(.musicSync, audio: loud(bass: 1)), seconds: 3)
        #expect(high.outerOpacity > low.outerOpacity + 0.1)
    }

    @Test func flowRotatesWhilePlaying() {
        var a = GlowAnimator()
        let first = run(&a, inputs(.flow, audio: loud(bass: 0.5)), seconds: 3)
        let second = run(&a, inputs(.flow, audio: loud(bass: 0.5)), seconds: 1)
        #expect(first.field != second.field)
        #expect(second.needsContinuousUpdates)
    }

    @Test func coloursTransitionSmoothly() {
        var a = GlowAnimator()
        _ = run(&a, inputs(.ambient), seconds: 2)
        var red = inputs(.ambient)
        red.colors = [RGBAColor(red: 1, green: 0, blue: 0)]
        let mid = a.next(red, dt: 1.0 / 60)
        #expect(mid.field[0].red < 1)             // not an instant jump
        #expect(mid.needsContinuousUpdates)
        let end = run(&a, red, seconds: 4)
        #expect(abs(end.field[0].red - 1) < 0.01)
    }

    @Test func opacitiesStayInRange() {
        var a = GlowAnimator()
        var big = inputs(.pulse, audio: AudioFeatures(level: 1, bass: 1, mid: 1, treble: 1, beat: 1, spectrum: [], isSilent: false))
        big.style.intensity = 1
        let f = run(&a, big, seconds: 2)
        for v in [f.outerOpacity, f.mediumOpacity, f.bandOpacity, f.highlightOpacity] { #expect((0...1).contains(v)) }
    }

    @Test func notchWrapPathDipsBelowTopEdge() {
        let notch = CGRect(x: 700, y: 1085, width: 200, height: 32)
        let wrapped = GlowGeometry(size: CGSize(width: 1600, height: 1117), cornerRadius: 10, notch: notch, notchMode: .wrap).path()
        let plain = GlowGeometry(size: CGSize(width: 1600, height: 1117), cornerRadius: 10, notch: notch, notchMode: .ignore).path()
        #expect(plain.boundingBox == CGRect(x: 0, y: 0, width: 1600, height: 1117))
        // The wrapped path passes through the bottom of the notch.
        let probe = CGPoint(x: 800, y: 1085)
        #expect(wrapped.copy(strokingWithWidth: 2, lineCap: .butt, lineJoin: .miter, miterLimit: 1).contains(probe))
        #expect(!plain.copy(strokingWithWidth: 2, lineCap: .butt, lineJoin: .miter, miterLimit: 1).contains(probe))
    }

    func luminance(_ c: RGBAColor) -> Double { c.red + c.green + c.blue }

    @Test func spectrumPutsBassAtTheBottomAndTrebleAtTheTop() {
        var a = GlowAnimator()
        let bassOnly = AudioFeatures(level: 0.8, bass: 1, mid: 0.1, treble: 0, beat: 0, spectrum: [], isSilent: false)
        let f = run(&a, inputs(.spectrum, audio: bassOnly), seconds: 3)
        let n = GlowAnimator.fieldResolution
        #expect(luminance(f.field[n * 3 / 4]) > luminance(f.field[n / 4]) * 2) // bottom centre vs top centre
    }

    @Test func cometHasALocalisedBrightHead() {
        var a = GlowAnimator()
        let f = run(&a, inputs(.comet, audio: loud(bass: 0.5)), seconds: 2)
        let values = f.field.map(luminance).sorted()
        #expect(values.last! > values[values.count / 2] * 2)
    }

    @Test func everyPresetProducesAFullField() {
        for preset in GlowPreset.allCases {
            var a = GlowAnimator()
            let f = run(&a, inputs(preset, audio: loud(bass: 0.6)), seconds: 1)
            #expect(f.field.count == GlowAnimator.fieldResolution)
            #expect(f.field.allSatisfy { (0...1).contains($0.red) && (0...1).contains($0.green) && (0...1).contains($0.blue) })
        }
    }

    @Test func hdrHeadroomOnlyWhenEnabled() {
        var a = GlowAnimator(), b = GlowAnimator()
        var hdr = inputs(.musicSync, audio: loud(bass: 1))
        hdr.hdr = true
        #expect(run(&a, hdr, seconds: 2).hdrHeadroom > 1)
        #expect(run(&b, inputs(.musicSync, audio: loud(bass: 1)), seconds: 2).hdrHeadroom == 1)
    }

    @Test func conicLocationsAreMonotonicAndUniformOnASquare() {
        let square = GlowGeometry(size: CGSize(width: 100, height: 100), cornerRadius: 0, notch: nil, notchMode: .ignore)
        let wide = GlowGeometry(size: CGSize(width: 1600, height: 1000), cornerRadius: 0, notch: nil, notchMode: .ignore)
        for g in [square, wide] {
            let locations = g.conicLocations(count: 64)
            #expect(locations.count == 65)
            #expect(zip(locations, locations.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(locations.first == 0 && locations.last == 1)
        }
        // On a square, equal edge lengths subtend equal angles at the corners.
        #expect(abs(square.conicLocations(count: 8)[1] - 0.125) < 1e-9)
        // On a wide display, the top-right corner (1/8 of the way round by angle in unit
        // space) is reached after only h/2 of the 2(w+h) perimeter.
        let atCorner = wide.conicLocations(count: 52)[5]  // 5/52 · 5200 = 500 = h/2
        #expect(abs(atCorner - 0.125) < 1e-9)
    }
}

struct GlowIdleHandoffTests {
    @Test func idleMotionPresetWithSteadyLightStopsRendering() {
        var style = GlowStyle()
        style.preset = .flow
        var animator = GlowAnimator()
        let idle = GlowInputs(style: style, idleBehavior: .steady, colors: ArtworkPalette.fallback.glowColors, isPlaying: false)
        var frame = animator.next(idle, dt: 1.0 / 60)
        for _ in 0..<600 { frame = animator.next(idle, dt: 1.0 / 60) }
        #expect(!frame.needsContinuousUpdates)
    }

    @Test func settledIdleOnlyWhenNothingIsPlayingAndColoursHaveSettled() {
        var style = GlowStyle()
        style.preset = .musicSync
        var animator = GlowAnimator()
        let idle = GlowInputs(style: style, idleBehavior: .breathe, colors: ArtworkPalette.fallback.glowColors, isPlaying: false)
        var frame = animator.next(idle, dt: 1.0 / 60)
        for _ in 0..<600 { frame = animator.next(idle, dt: 1.0 / 60) }
        #expect(frame.isSettledIdle)

        var playing = idle
        playing.isPlaying = true
        #expect(!animator.next(playing, dt: 1.0 / 60).isSettledIdle)
    }
}

struct GlowFieldBlurTests {
    @Test func blurPreservesEnergyAndWraps() {
        var field = [RGBAColor](repeating: .black, count: 64)
        field[0] = .white
        let blurred = GlowAnimator.circularBlur(field, sigma: 3.5)
        let total = blurred.reduce(0) { $0 + $1.red }
        #expect(abs(total - 1) < 1e-9)
        #expect(blurred[63].red > 0 && blurred[1].red > 0)   // spreads both ways across the seam
        #expect(abs(blurred[63].red - blurred[1].red) < 1e-12)
        #expect(blurred[0].red < 0.2)                       // a sharp spike becomes soft
    }
}
