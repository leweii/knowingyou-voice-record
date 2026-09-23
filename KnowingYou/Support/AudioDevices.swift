import CoreAudio
import Foundation

struct AudioInputDevice: Sendable, Identifiable, Equatable, Hashable {
    let uid: String
    let name: String
    var id: String { uid }
}

/// Pure Core Audio enumeration, decoupled from the observable wrapper below
/// so it's directly unit-testable without touching the main actor.
enum AudioDevices {
    static func currentInputDevices() -> [AudioInputDevice] {
        guard let deviceIDs = allDeviceIDs() else { return [] }
        return deviceIDs.compactMap { deviceID in
            guard hasInputStreams(deviceID),
                  let uid = uid(for: deviceID),
                  let name = name(for: deviceID) else {
                return nil
            }
            return AudioInputDevice(uid: uid, name: name)
        }
    }

    static func allDeviceIDs() -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return nil }
        return deviceIDs
    }

    static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    static func name(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }
        return name as String
    }

    static func uid(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }
        return uid as String
    }
}

/// Live-updating wrapper for the settings UI (R4). Listens for
/// `kAudioHardwarePropertyDevices` changes so plugging/unplugging a mic
/// refreshes the picker without a restart.
@MainActor
@Observable
final class AudioDeviceMonitor {
    static let shared = AudioDeviceMonitor()

    private(set) var inputDevices: [AudioInputDevice] = []

    private init() {
        refresh()
        startListening()
    }

    func refresh() {
        inputDevices = AudioDevices.currentInputDevices()
    }

    private func startListening() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            self?.refresh()
        }
    }
}
