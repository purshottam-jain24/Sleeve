import CoreAudio
import Foundation
import os

/// Fixed-size mono ring buffer shared between the real-time capture thread and the analyzer.
///
/// Holds only the last few thousand samples in memory. Nothing is ever persisted;
/// old samples are overwritten continuously.
public final class AudioSampleBuffer: Sendable {
    private struct State {
        var samples: [Float]
        var writeIndex = 0
        var totalWritten = 0
        var sampleRate: Double = 48_000
        var lastWriteUptime: UInt64 = 0
    }

    private let state: OSAllocatedUnfairLock<State>
    public let capacity: Int

    public init(capacity: Int = 8_192) {
        self.capacity = capacity
        state = OSAllocatedUnfairLock(initialState: State(samples: [Float](repeating: 0, count: capacity)))
    }

    public func reset(sampleRate: Double) {
        state.withLock {
            for i in $0.samples.indices { $0.samples[i] = 0 }
            $0.writeIndex = 0
            $0.totalWritten = 0
            $0.sampleRate = sampleRate
        }
    }

    /// Downmixes and appends Float32 PCM. Safe to call from a real-time audio thread
    /// (no allocation; holds an unfair lock for a few microseconds).
    public func write(_ list: UnsafeMutableAudioBufferListPointer, frameCount: Int, interleavedChannels: Int) {
        guard frameCount > 0, !list.isEmpty else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        state.withLockUnchecked { s in
            let cap = s.samples.count
            if list.count == 1 {
                // Interleaved (or mono) single buffer.
                guard let data = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                let channels = max(1, interleavedChannels)
                let available = Int(list[0].mDataByteSize) / (MemoryLayout<Float>.size * channels)
                let frames = min(frameCount, available)
                let scale = 1 / Float(channels)
                for f in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += data[f * channels + c] }
                    s.samples[s.writeIndex] = sum * scale
                    s.writeIndex = (s.writeIndex + 1) % cap
                }
                s.totalWritten &+= frames
            } else {
                // Non-interleaved: one buffer per channel.
                var frames = frameCount
                for buffer in list {
                    frames = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                }
                let scale = 1 / Float(list.count)
                for f in 0..<frames {
                    var sum: Float = 0
                    for buffer in list {
                        if let data = buffer.mData?.assumingMemoryBound(to: Float.self) { sum += data[f] }
                    }
                    s.samples[s.writeIndex] = sum * scale
                    s.writeIndex = (s.writeIndex + 1) % cap
                }
                s.totalWritten &+= frames
            }
            s.lastWriteUptime = now
        }
    }

    /// Test/utility entry point for already-mono samples.
    public func write(mono samples: [Float]) {
        state.withLockUnchecked { s in
            for sample in samples {
                s.samples[s.writeIndex] = sample
                s.writeIndex = (s.writeIndex + 1) % s.samples.count
            }
            s.totalWritten &+= samples.count
            s.lastWriteUptime = DispatchTime.now().uptimeNanoseconds
        }
    }

    /// Copies the most recent `destination.count` samples, oldest first.
    /// - Returns: the sample rate and seconds since the last write (`.infinity` if never).
    @discardableResult
    public func copyLatest(into destination: inout [Float]) -> (sampleRate: Double, staleness: Double) {
        state.withLockUnchecked { s in
            let cap = s.samples.count
            let n = min(destination.count, cap)
            var read = (s.writeIndex - n + cap) % cap
            for i in 0..<n {
                destination[i] = s.samples[read]
                read = (read + 1) % cap
            }
            let staleness = s.lastWriteUptime == 0
                ? Double.infinity
                : Double(DispatchTime.now().uptimeNanoseconds &- s.lastWriteUptime) / 1e9
            return (s.sampleRate, staleness)
        }
    }
}
