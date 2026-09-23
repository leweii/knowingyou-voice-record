import CoreAudio

/// Abstracts the one Core Audio query `MeetingDetector` actually needs, so
/// tests can inject a fake list of (pid, bundleID) pairs instead of depending
/// on real hardware/processes.
protocol ProcessObjectReading: Sendable {
    func activeInputProcesses() -> [(pid: pid_t, bundleID: String)]
}

/// Ports the S06 spike's `who-uses-mic` enumeration
/// (Spikes/ProcessTapSpike/Sources/ProcessTapSpike/main.swift) into the app,
/// with one addition: excludes KnowingYou's own process object, which
/// otherwise could show up if this app itself is ever mid-recording (its own
/// mic use isn't a "meeting").
struct CoreAudioProcessObjectReader: ProcessObjectReading {
    func activeInputProcesses() -> [(pid: pid_t, bundleID: String)] {
        let ownProcessID = CoreAudioUtils.ownProcessObjectID()
        var results: [(pid: pid_t, bundleID: String)] = []
        for processID in Self.allProcessObjectIDs() {
            guard processID != ownProcessID else { continue }
            guard Self.isRunningInput(processID) == true else { continue }
            guard let bundleID = CoreAudioUtils.stringProperty(processID, selector: kAudioProcessPropertyBundleID),
                  let pid = Self.pid(processID) else { continue }
            results.append((pid: pid, bundleID: bundleID))
        }
        return results
    }

    private static func allProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids)
        return status == noErr ? ids : []
    }

    private static func isRunningInput(_ processID: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value != 0
    }

    private static func pid(_ processID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processID, &address) else { return nil }
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
