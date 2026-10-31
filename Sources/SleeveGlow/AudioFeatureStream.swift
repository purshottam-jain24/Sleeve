import AfterglowAudio
import Foundation
import Observation
import QuartzCore

/// One analyzer shared by the on-screen glow and every preview, so the FFT runs once
/// per frame no matter how many surfaces are drawing.
@MainActor
@Observable
public final class AudioFeatureStream {
    /// Number of visible previews that want live audio. Read by the app to decide
    /// whether capture should run while the glow itself is off.
    public private(set) var previewClients = 0

    @ObservationIgnored public let audio: AudioCaptureService
    @ObservationIgnored public var tuning = AnalyzerTuning()
    @ObservationIgnored private let analyzer = AudioAnalyzer()
    @ObservationIgnored private var samples: [Float]
    @ObservationIgnored private var lastTime: CFTimeInterval?
    @ObservationIgnored private var cached = AudioFeatures.silent
    @ObservationIgnored private var lastSoundTime: CFTimeInterval = -.infinity

    public init(audio: AudioCaptureService) {
        self.audio = audio
        samples = [Float](repeating: 0, count: analyzer.fftSize)
    }

    /// Features for the frame at `time` (a display-link timestamp). Calls within the
    /// same frame return the cached result.
    public func features(at time: CFTimeInterval) -> AudioFeatures {
        if let lastTime, abs(time - lastTime) < 0.004 { return cached }
        var dt = lastTime.map { time - $0 } ?? 1.0 / 60
        if dt <= 0 || dt > 0.5 { dt = 1.0 / 60 }
        lastTime = time

        if audio.isRunning {
            let (sampleRate, staleness) = audio.buffer.copyLatest(into: &samples)
            cached = staleness < 0.5
                ? analyzer.process(samples: samples, sampleRate: sampleRate, dt: dt, tuning: tuning)
                : analyzer.decay(dt: dt)
        } else {
            cached = analyzer.decay(dt: dt)
        }
        if !cached.isSilent { lastSoundTime = time }
        return cached
    }

    /// `true` while real system audio has been heard within the last 1.5 s.
    public func hasLiveSignal(at time: CFTimeInterval) -> Bool {
        audio.isRunning && time - lastSoundTime < 1.5
    }

    public func addPreviewClient() { previewClients += 1 }
    public func removePreviewClient() { previewClients = max(0, previewClients - 1) }
}

/// A synthetic 120 BPM groove used only to demonstrate presets in previews when no
/// music is playing. The UI labels it as a demo; it never drives the real overlay.
public enum DemoSignal {
    public static func features(at time: Double) -> AudioFeatures {
        let beatLength = 0.5
        let phase = time.truncatingRemainder(dividingBy: beatLength) / beatLength
        let bar = Int(time / beatLength) % 4
        let kick = Float(exp(-phase * 7))
        let hat = Float(exp(-abs(phase - 0.5) * 18)) * 0.8
        let snare = (bar == 1 || bar == 3) ? Float(exp(-phase * 9)) * 0.7 : 0
        let melody = Float(0.45 + 0.25 * sin(time * 1.3) + 0.15 * sin(time * 3.1))
        let bass = min(1, 0.25 + 0.75 * kick)
        let mid = min(1, melody + 0.3 * snare)
        let treble = min(1, 0.25 + hat + 0.2 * snare)
        let bands = AudioFeatures.bandCount
        let spectrum = (0..<bands).map { i -> Float in
            let x = Float(i) / Float(bands - 1)
            let wobble = Float(0.12 * sin(time * 2.3 + Double(i) * 0.7))
            let shape = bass * max(0, 1 - x * 3) + mid * exp(-pow((x - 0.45) * 3.2, 2)) + treble * max(0, x * 1.4 - 0.4)
            return min(1, max(0, shape + wobble))
        }
        return AudioFeatures(
            level: min(1, 0.35 + 0.4 * kick + 0.2 * melody),
            bass: bass, mid: mid, treble: treble,
            beat: phase < 0.06 ? 1 : kick,
            spectrum: spectrum, isSilent: false
        )
    }
}
