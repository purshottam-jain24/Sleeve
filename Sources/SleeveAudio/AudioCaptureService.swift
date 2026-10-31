import CoreAudio
import Foundation
import Observation

public enum AudioCaptureBackendKind: String, Sendable {
    case processTap = "Core Audio process tap"
    case screenCaptureKit = "ScreenCaptureKit"
}

/// Backends do their own threading: `start` and `stop` must never block the caller,
/// because system audio APIs can stall while a permission prompt is showing.
protocol AudioCaptureBackend: AnyObject, Sendable {
    var kind: AudioCaptureBackendKind { get }
    func start(into buffer: AudioSampleBuffer) async throws
    func stop()
}

public enum AudioCaptureState: Sendable, Equatable {
    case idle
    case starting
    case running(AudioCaptureBackendKind)
    case failed(String)
}

/// Owns system-audio capture for the edge glow.
///
/// Captured samples only ever live in `buffer` (a small in-memory ring); they are never
/// recorded, written to disk or sent anywhere.
@MainActor
@Observable
public final class AudioCaptureService {
    public private(set) var state: AudioCaptureState = .idle
    /// Set when starting takes long enough that macOS is probably showing (or waiting on)
    /// the System Audio Recording permission prompt.
    public private(set) var isWaitingForPermission = false
    public let buffer = AudioSampleBuffer()

    @ObservationIgnored private var backend: (any AudioCaptureBackend)?
    @ObservationIgnored private var wantsCapture = false
    @ObservationIgnored private var outputListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var generation = 0

    public init() {}

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// `true` when samples arrived within the last second.
    public var isReceivingAudio: Bool {
        var probe = [Float](repeating: 0, count: 1)
        return buffer.copyLatest(into: &probe).staleness < 1
    }

    public func setActive(_ active: Bool) {
        guard active != wantsCapture else { return }
        wantsCapture = active
        if active { start() } else { stop() }
    }

    /// Stops and restarts capture, e.g. after wake or an output-device change.
    public func restart() {
        guard wantsCapture else { return }
        stop(keepIntent: true)
        start()
    }

    private func start() {
        guard backend == nil else { return }
        generation += 1
        let token = generation
        state = .starting
        let backend = makeBackend()
        self.backend = backend
        isWaitingForPermission = false
        Task {
            try? await Task.sleep(for: .seconds(3))
            if token == generation, state == .starting { isWaitingForPermission = true }
        }
        Task {
            do {
                try await backend.start(into: buffer)
                isWaitingForPermission = false
                guard token == generation else { backend.stop(); return }
                state = .running(backend.kind)
                installOutputListener()
            } catch {
                isWaitingForPermission = false
                guard token == generation else { return }
                backend.stop()
                self.backend = nil
                state = .failed(String(describing: error))
            }
        }
    }

    private func stop(keepIntent: Bool = false) {
        generation += 1
        backend?.stop()
        backend = nil
        removeOutputListener()
        isWaitingForPermission = false
        if !keepIntent { state = .idle }
    }

    private func makeBackend() -> any AudioCaptureBackend {
        let forceSCK = ProcessInfo.processInfo.environment["SLEEVE_FORCE_SCREENCAPTUREKIT"] == "1"
        if #available(macOS 14.2, *), !forceSCK {
            return ProcessTapCapture()
        }
        return ScreenCaptureAudioCapture()
    }

    // The aggregate device is bound to the output device that was default at start,
    // so switching to AirPods etc. requires rebuilding the tap.
    private func installOutputListener() {
        guard outputListener == nil else { return }
        var address = CoreAudioQuery.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.restart() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            outputListener = listener
        }
    }

    private func removeOutputListener() {
        guard let listener = outputListener else { return }
        var address = CoreAudioQuery.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        outputListener = nil
    }
}
