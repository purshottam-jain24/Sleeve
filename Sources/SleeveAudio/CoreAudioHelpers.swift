import CoreAudio
import Foundation

public struct CoreAudioError: Error, Sendable, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public var description: String {
        let code = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let fourCC = bytes.allSatisfy { (32...126).contains($0) } ? " '\(String(decoding: bytes, as: UTF8.self))'" : ""
        return "\(operation) failed (\(status)\(fourCC))"
    }
}

func check(_ status: OSStatus, _ operation: String) throws(CoreAudioError) {
    guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
}

enum CoreAudioQuery {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func defaultSystemOutputDevice() throws(CoreAudioError) -> AudioDeviceID {
        var address = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device),
            "Reading default output device"
        )
        return device
    }

    static func deviceUID(_ device: AudioDeviceID) throws(CoreAudioError) -> String {
        var address = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid), "Reading device UID")
        guard let uid else { throw CoreAudioError(operation: "Reading device UID", status: -1) }
        return uid.takeRetainedValue() as String
    }

    static func processObject(for pid: pid_t) throws(CoreAudioError) -> AudioObjectID {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
            ),
            "Translating PID to process object"
        )
        return object
    }

    static func tapFormat(_ tap: AudioObjectID) throws(CoreAudioError) -> AudioStreamBasicDescription {
        var address = address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "Reading tap format")
        return format
    }
}
