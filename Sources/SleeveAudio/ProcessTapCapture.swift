import CoreAudio
import Foundation

/// Captures the system audio mix (minus our own process) with a Core Audio process tap.
///
/// Requires macOS 14.2 and the "System Audio Recording" permission
/// (`NSAudioCaptureUsageDescription`). Audio still plays normally (`.unmuted`).
///
/// Every HAL call runs on `controlQueue`, never the main thread: creating the IO proc
/// can block for as long as the system permission prompt is on screen.
@available(macOS 14.2, *)
final class ProcessTapCapture: AudioCaptureBackend, @unchecked Sendable {
    let kind: AudioCaptureBackendKind = .processTap

    // Only touched on `controlQueue`.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    private let controlQueue = DispatchQueue(label: "app.sleeve.audio.tap.control", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "app.sleeve.audio.tap.io", qos: .userInteractive)

    func start(into buffer: AudioSampleBuffer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controlQueue.async {
                do {
                    try self.startTap(into: buffer)
                    continuation.resume()
                } catch {
                    self.teardown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        controlQueue.async { self.teardown() }
    }

    private func startTap(into buffer: AudioSampleBuffer) throws(CoreAudioError) {
        let ownProcess = try? CoreAudioQuery.processObject(for: ProcessInfo.processInfo.processIdentifier)
        let excluded = ownProcess.map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Sleeve Edge Glow"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating process tap")

        let outputUID = try CoreAudioQuery.deviceUID(CoreAudioQuery.defaultSystemOutputDevice())
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sleeve Tap",
            kAudioAggregateDeviceUIDKey: "app.sleeve.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "Creating aggregate device")

        let format = try CoreAudioQuery.tapFormat(tapID)
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else {
            throw CoreAudioError(operation: "Unsupported tap format", status: OSStatus(format.mFormatID))
        }
        let interleavedChannels = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            ? 1 : Int(format.mChannelsPerFrame)
        buffer.reset(sampleRate: format.mSampleRate)

        try check(
            AudioDeviceCreateIOProcIDWithBlock(
                &ioProcID, aggregateID, ioQueue,
                Self.makeIOBlock(buffer: buffer, interleavedChannels: interleavedChannels)
            ),
            "Creating IO proc"
        )
        try check(AudioDeviceStart(aggregateID, ioProcID), "Starting aggregate device")
    }

    private static func makeIOBlock(buffer: AudioSampleBuffer, interleavedChannels: Int) -> AudioDeviceIOBlock {
        { _, inputData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            guard let first = list.first else { return }
            let bytesPerFrame = MemoryLayout<Float>.size * interleavedChannels
            buffer.write(list, frameCount: Int(first.mDataByteSize) / bytesPerFrame, interleavedChannels: interleavedChannels)
        }
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}
