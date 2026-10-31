import CoreMedia
import Foundation
import ScreenCaptureKit

/// Fallback for macOS 14.0–14.1, where process taps are unavailable.
///
/// Uses ScreenCaptureKit's audio stream, which requires the Screen Recording permission.
/// Video output is not consumed; the stream is configured with a 2×2 frame at 1 fps.
final class ScreenCaptureAudioCapture: NSObject, AudioCaptureBackend, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let kind: AudioCaptureBackendKind = .screenCaptureKit

    // `stream` is guarded by `lock`; `buffer` is written once before capture starts.
    private let lock = NSLock()
    private var stream: SCStream?
    private var buffer: AudioSampleBuffer?
    private let queue = DispatchQueue(label: "app.afterglow.audio.sck", qos: .userInteractive)

    func start(into buffer: AudioSampleBuffer) async throws {
        self.buffer = buffer
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw CoreAudioError(operation: "Finding a display for audio capture", status: -1)
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        buffer.reset(sampleRate: 48_000)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        lock.withLock { self.stream = stream }
    }

    func stop() {
        let stream = lock.withLock { () -> SCStream? in
            defer { self.stream = nil }
            return self.stream
        }
        Task { try? await stream?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let buffer, sampleBuffer.isValid else { return }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        var interleavedChannels = 1
        if let description = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            guard asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 else { return }
            if asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 {
                interleavedChannels = Int(asbd.mChannelsPerFrame)
            }
        }
        try? sampleBuffer.withAudioBufferList { list, _ in
            buffer.write(list, frameCount: frames, interleavedChannels: interleavedChannels)
        }
    }
}
