import Foundation
import Testing
@testable import SleeveAudio

struct AudioAnalyzerTests {
    let rate = 48_000.0

    func sine(_ freq: Double, amplitude: Float = 0.5, count: Int = 2_048, offset: Int = 0) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * freq * Double($0 + offset) / rate)) }
    }

    func settle(_ analyzer: AudioAnalyzer, _ samples: [Float], frames: Int = 60) -> AudioFeatures {
        var f = AudioFeatures.silent
        for _ in 0..<frames { f = analyzer.process(samples: samples, sampleRate: rate, dt: 1.0 / 60, tuning: AnalyzerTuning()) }
        return f
    }

    @Test func lowToneDrivesBass() {
        let f = settle(AudioAnalyzer(), sine(60))
        #expect(!f.isSilent)
        #expect(f.bass > 0.6)
        #expect(f.treble < 0.2)
    }

    @Test func highToneDrivesTreble() {
        let f = settle(AudioAnalyzer(), sine(8_000))
        #expect(f.treble > 0.6)
        #expect(f.bass < 0.2)
    }

    @Test func silenceIsSilent() {
        let f = settle(AudioAnalyzer(), [Float](repeating: 0, count: 2_048))
        #expect(f.isSilent)
        #expect(f.level == 0 && f.bass == 0)
    }

    @Test func detectsKickDrumOnsets() {
        let analyzer = AudioAnalyzer()
        let quiet = sine(60, amplitude: 0.02)
        let kick = sine(60, amplitude: 0.9)
        var beats = 0
        // 120 BPM: a kick every 30 frames at 60 fps, for 4 seconds.
        for frame in 0..<240 {
            let f = analyzer.process(samples: frame % 30 < 3 ? kick : quiet, sampleRate: rate, dt: 1.0 / 60, tuning: AnalyzerTuning())
            if f.beat > 0.99 { beats += 1 }
        }
        #expect((6...8).contains(beats))
    }

    @Test func ringBufferReturnsLatestSamplesInOrder() {
        let buffer = AudioSampleBuffer(capacity: 8)
        buffer.write(mono: (1...11).map(Float.init))
        var out = [Float](repeating: 0, count: 4)
        let (_, staleness) = buffer.copyLatest(into: &out)
        #expect(out == [8, 9, 10, 11])
        #expect(staleness < 1)
    }
}
