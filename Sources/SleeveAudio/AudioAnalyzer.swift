import Accelerate
import Foundation

public struct AudioFeatures: Sendable, Equatable {
    /// All values are normalised to 0...1 after auto-gain and sensitivity.
    public var level: Float
    public var bass: Float
    public var mid: Float
    public var treble: Float
    /// 1 on a detected beat, decaying towards 0.
    public var beat: Float
    /// Log-spaced bands from ~30 Hz to ~16 kHz.
    public var spectrum: [Float]
    public var isSilent: Bool

    public static let bandCount = 24

    public init(level: Float, bass: Float, mid: Float, treble: Float, beat: Float, spectrum: [Float], isSilent: Bool) {
        self.level = level
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.beat = beat
        self.spectrum = spectrum
        self.isSilent = isSilent
    }

    public static let silent = AudioFeatures(
        level: 0, bass: 0, mid: 0, treble: 0, beat: 0,
        spectrum: [Float](repeating: 0, count: bandCount), isSilent: true
    )
}

public struct AnalyzerTuning: Sendable, Equatable {
    /// 0...2
    public var sensitivity: Float
    /// 0...2
    public var bassSensitivity: Float
    /// 0 = very smooth, 1 = very snappy.
    public var responseSpeed: Float

    public init(sensitivity: Float = 1, bassSensitivity: Float = 1, responseSpeed: Float = 0.5) {
        self.sensitivity = sensitivity
        self.bassSensitivity = bassSensitivity
        self.responseSpeed = responseSpeed
    }
}

/// Turns raw PCM into smoothed musical features using a 2048-point vDSP FFT.
///
/// Not thread-safe: call `process` from one thread (the glow's display-link tick).
public final class AudioAnalyzer {
    public let fftSize = 2_048
    private let log2n: vDSP_Length = 11
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]

    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]

    // Smoothed outputs.
    private var level: Float = 0
    private var bass: Float = 0
    private var mid: Float = 0
    private var treble: Float = 0
    private var beat: Float = 0
    private var spectrum = [Float](repeating: 0, count: AudioFeatures.bandCount)

    // Auto-gain peaks so quiet and loud masters both use the full range.
    private var levelPeak: Float = 1e-3
    private var bassPeak: Float = 1e-3
    private var midPeak: Float = 1e-3
    private var treblePeak: Float = 1e-3
    private var spectrumPeak: Float = 1e-3

    // Beat detection.
    private var bassAverage: Float = 0
    private var timeSinceBeat: Double = 1

    public init() {
        fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize / 2)
        imag = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    /// - Parameters:
    ///   - samples: at least `fftSize` mono samples, oldest first; only the last `fftSize` are used.
    ///   - dt: seconds since the previous call, used for frame-rate-independent smoothing.
    public func process(samples: [Float], sampleRate: Double, dt: Double, tuning: AnalyzerTuning) -> AudioFeatures {
        precondition(samples.count >= fftSize)
        let dt = min(max(dt, 1.0 / 240), 0.25)
        let input = samples.suffix(fftSize)

        let rms = vDSP.rootMeanSquare(input)
        let isSilent = rms < 1e-4

        vDSP.multiply(input, window, result: &windowed)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                let half = fftSize / 2
                windowed.withUnsafeBufferPointer { p in
                    p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &magnitudes)
            }
        }
        magnitudes[0] = 0 // DC / Nyquist packing
        vForce.sqrt(magnitudes, result: &magnitudes)

        let binWidth = sampleRate / Double(fftSize)
        func bandEnergy(_ low: Double, _ high: Double) -> Float {
            let lo = max(1, Int(low / binWidth))
            let hi = min(magnitudes.count - 1, max(lo, Int(high / binWidth)))
            return vDSP.mean(magnitudes[lo...hi])
        }
        let rawBass = bandEnergy(20, 250)
        let rawMid = bandEnergy(250, 4_000)
        let rawTreble = bandEnergy(4_000, 14_000)

        // Auto-gain: peaks decay over ~4 s so the glow adapts to the track's loudness.
        let peakDecay = Float(exp(-dt / 4))
        func normalise(_ value: Float, peak: inout Float, floor: Float) -> Float {
            peak = max(value, peak * peakDecay, floor)
            return min(1, value / peak)
        }
        let sens = tuning.sensitivity
        let nLevel = min(1, normalise(rms, peak: &levelPeak, floor: 0.02) * sens)
        let nBass = min(1, normalise(rawBass, peak: &bassPeak, floor: 0.05) * sens * tuning.bassSensitivity)
        let nMid = min(1, normalise(rawMid, peak: &midPeak, floor: 0.02) * sens)
        let nTreble = min(1, normalise(rawTreble, peak: &treblePeak, floor: 0.01) * sens)

        // Attack/release smoothing; `responseSpeed` shortens both time constants.
        let r = Double(min(max(tuning.responseSpeed, 0), 1))
        let attack = Float(1 - exp(-dt / (0.10 - 0.085 * r)))
        let release = Float(1 - exp(-dt / (0.55 - 0.42 * r)))
        func smooth(_ current: inout Float, _ target: Float) {
            current += (target - current) * (target > current ? attack : release)
        }
        let silentGate: Float = isSilent ? 0 : 1
        smooth(&level, nLevel * silentGate)
        smooth(&bass, nBass * silentGate)
        smooth(&mid, nMid * silentGate)
        smooth(&treble, nTreble * silentGate)

        // Spectrum bands, log-spaced 30 Hz – 16 kHz.
        let bands = AudioFeatures.bandCount
        var rawBands = [Float](repeating: 0, count: bands)
        let minF = 30.0, maxF = 16_000.0
        for b in 0..<bands {
            let lo = minF * pow(maxF / minF, Double(b) / Double(bands))
            let hi = minF * pow(maxF / minF, Double(b + 1) / Double(bands))
            rawBands[b] = bandEnergy(lo, hi)
        }
        let maxBand = rawBands.max() ?? 0
        spectrumPeak = max(maxBand, spectrumPeak * peakDecay, 0.02)
        for b in 0..<bands {
            smooth(&spectrum[b], min(1, rawBands[b] / spectrumPeak * sens) * silentGate)
        }

        // Beat: bass flux well above its recent average, at most ~4 per second.
        let averageRate = Float(1 - exp(-dt / 0.9))
        timeSinceBeat += dt
        if !isSilent, rawBass > bassAverage * 1.45, rawBass > bassPeak * 0.3, timeSinceBeat > 0.24 {
            beat = 1
            timeSinceBeat = 0
        } else {
            beat *= Float(exp(-dt / 0.16))
        }
        bassAverage += (rawBass - bassAverage) * averageRate

        return AudioFeatures(
            level: level, bass: bass, mid: mid, treble: treble, beat: beat,
            spectrum: spectrum, isSilent: isSilent
        )
    }

    /// Glides all outputs to zero when no audio is arriving.
    public func decay(dt: Double) -> AudioFeatures {
        let f = Float(exp(-max(dt, 0) / 0.35))
        level *= f; bass *= f; mid *= f; treble *= f; beat *= f
        for i in spectrum.indices { spectrum[i] *= f }
        return AudioFeatures(level: level, bass: bass, mid: mid, treble: treble, beat: beat, spectrum: spectrum, isSilent: true)
    }
}
