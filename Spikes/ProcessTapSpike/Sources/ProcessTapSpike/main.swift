// ProcessTapSpike — throwaway CLI for docs/specs/S06. Not shipped, not held
// to the same quality bar as the app. Two subcommands:
//   who-uses-mic [--watch]   enumerate Core Audio process objects reporting mic use
//   tap --seconds N --out path.caf   attempt a global system-audio Process Tap
//
// References: insidegui/AudioCap (ProcessTap.swift, AudioProcessController.swift).

import AVFoundation
import CoreAudio
import Foundation

// MARK: - Core Audio process object helpers

func allProcessObjectIDs() -> [AudioObjectID] {
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
    guard status == noErr else { return [] }
    return ids
}

func processIsRunningInput(_ processID: AudioObjectID) -> Bool? {
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

func processBundleID(_ processID: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyBundleID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectHasProperty(processID, &address) else { return nil }
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) { ptr in
        AudioObjectGetPropertyData(processID, &address, 0, nil, &size, ptr)
    }
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

func processPID(_ processID: AudioObjectID) -> pid_t? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectHasProperty(processID, &address) else { return nil }
    var value: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)
    let status = AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &value)
    guard status == noErr else { return nil }
    return value
}

// MARK: - who-uses-mic

func runWhoUsesMic(watch: Bool) {
    func snapshot() {
        let processes = allProcessObjectIDs()
        var anyRunning = false
        for processID in processes {
            guard processIsRunningInput(processID) == true else { continue }
            anyRunning = true
            let bundle = processBundleID(processID) ?? "?"
            let pidText = processPID(processID).map(String.init) ?? "?"
            print("[\(Date())] pid=\(pidText) bundleID=\(bundle) IsRunningInput=true")
        }
        if !anyRunning {
            print("[\(Date())] no process reports IsRunningInput=true (\(processes.count) process objects enumerated)")
        }
    }

    // Device-level listener: fires when any device starts/stops running.
    var deviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    if let devices = { () -> [AudioObjectID]? in
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids
    }() {
        for deviceID in devices {
            AudioObjectAddPropertyListenerBlock(deviceID, &deviceAddress, DispatchQueue.main) { _, _ in
                print("[\(Date())] device-level listener fired for device \(deviceID)")
            }
        }
        print("Registered device-level kAudioDevicePropertyDeviceIsRunningSomewhere listeners on \(devices.count) devices.")
    }

    // Process-level listener on the process-object-list itself (fires when
    // processes appear/disappear, NOT necessarily when IsRunningInput flips —
    // plan §5.1 says this doesn't reliably fire on macOS 26; this spike is
    // how we'd confirm that on a real machine).
    var processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processListAddress, DispatchQueue.main) { _, _ in
        print("[\(Date())] process-object-list listener fired")
    }

    snapshot()
    guard watch else { return }
    print("Watching every 500ms, Ctrl-C to stop.")
    while true {
        Thread.sleep(forTimeInterval: 0.5)
        snapshot()
    }
}

// MARK: - tap

func defaultOutputDeviceUID() -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else { return nil }

    var uidAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var uid: Unmanaged<CFString>?
    var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &uid) { ptr in
        AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, ptr)
    }
    guard status == noErr, let uid else { return nil }
    return uid.takeRetainedValue() as String
}

func runTap(seconds: Double, outputPath: String) {
    var pidToTranslate = getpid()
    var translateAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var ownProcessObjectID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let translateStatus = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &translateAddress,
        UInt32(MemoryLayout<pid_t>.size), &pidToTranslate, &size, &ownProcessObjectID
    )
    print("translate own pid -> process object: status=\(translateStatus) ownProcessObjectID=\(ownProcessObjectID)")

    let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObjectID])
    tapDescription.isPrivate = true
    tapDescription.muteBehavior = .unmuted

    var tapID = AudioObjectID(kAudioObjectUnknown)
    let createStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
    print("AudioHardwareCreateProcessTap: status=\(createStatus) tapID=\(tapID)")

    guard createStatus == noErr else {
        print("""
        Tap creation failed with OSStatus \(createStatus). This is the code \
        S08's Permissions.systemAudioProbe should treat as "系统音频录制 not \
        granted".
        """)
        return
    }

    // Surprise (see the spike report): tap *creation* succeeded with zero
    // permission prompt. Push further into the aggregate device + IOProc
    // path, since that's the actual data point S08 needs.
    guard let outputUID = defaultOutputDeviceUID() else {
        print("could not resolve default output device UID; aborting")
        AudioHardwareDestroyProcessTap(tapID)
        return
    }
    print("default output device UID: \(outputUID)")

    let tapUUID = tapDescription.uuid.uuidString
    let aggregateDescription: [String: Any] = [
        kAudioAggregateDeviceNameKey: "ProcessTapSpike-Aggregate",
        kAudioAggregateDeviceUIDKey: "com.jakobhe.knowingyou.spike.aggregate.\(UUID().uuidString)",
        kAudioAggregateDeviceMainSubDeviceKey: outputUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [
            [kAudioSubDeviceUIDKey: outputUID],
        ],
        kAudioAggregateDeviceTapListKey: [
            [kAudioSubTapUIDKey: tapUUID, kAudioSubTapDriftCompensationKey: true],
        ],
    ]

    var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
    print("AudioHardwareCreateAggregateDevice: status=\(aggregateStatus) aggregateDeviceID=\(aggregateDeviceID)")
    guard aggregateStatus == noErr else {
        AudioHardwareDestroyProcessTap(tapID)
        return
    }

    var formatAddress = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var asbd = AudioStreamBasicDescription()
    var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let formatStatus = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &asbdSize, &asbd)
    print("tap format status=\(formatStatus) sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame)")

    guard let avFormat = AVAudioFormat(streamDescription: &asbd) else {
        print("could not build AVAudioFormat from tap ASBD")
        AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        AudioHardwareDestroyProcessTap(tapID)
        return
    }

    guard let file = try? AVAudioFile(
        forWriting: URL(fileURLWithPath: outputPath),
        settings: avFormat.settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: avFormat.isInterleaved
    ) else {
        print("could not open output file at \(outputPath)")
        AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        AudioHardwareDestroyProcessTap(tapID)
        return
    }

    var totalFrames: Int64 = 0
    var writeErrorLogged = false
    var ioProcID: AudioDeviceIOProcID?
    let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil) { _, inputData, _, _, _ in
        guard let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, bufferListNoCopy: inputData, deallocator: nil) else {
            if !writeErrorLogged { print("AVAudioPCMBuffer(bufferListNoCopy:) returned nil"); writeErrorLogged = true }
            return
        }
        totalFrames += Int64(buffer.frameLength)
        do {
            try file.write(from: buffer)
        } catch {
            if !writeErrorLogged { print("file.write failed: \(error)"); writeErrorLogged = true }
        }
    }
    print("AudioDeviceCreateIOProcIDWithBlock: status=\(ioStatus)")
    guard ioStatus == noErr, let ioProcID else {
        AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        AudioHardwareDestroyProcessTap(tapID)
        return
    }

    let startStatus = AudioDeviceStart(aggregateDeviceID, ioProcID)
    print("AudioDeviceStart: status=\(startStatus) — this is the call most likely to actually require 系统音频录制 permission")
    if startStatus == noErr {
        print("Capturing \(seconds)s of system audio to \(outputPath) ...")
        Thread.sleep(forTimeInterval: seconds)
    }

    AudioDeviceStop(aggregateDeviceID, ioProcID)
    AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
    AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
    AudioHardwareDestroyProcessTap(tapID)

    print("Done. totalFrames captured=\(totalFrames)")
}

// MARK: - Entry point

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else {
    print("usage: ProcessTapSpike who-uses-mic [--watch] | tap --seconds N --out path.caf")
    exit(1)
}

switch command {
case "who-uses-mic":
    runWhoUsesMic(watch: arguments.contains("--watch"))
case "tap":
    let rest = Array(arguments.dropFirst())
    var seconds = 5.0
    var outputPath = "tap-output.caf"
    var index = 0
    while index < rest.count {
        switch rest[index] {
        case "--seconds":
            index += 1
            if index < rest.count, let value = Double(rest[index]) { seconds = value }
        case "--out":
            index += 1
            if index < rest.count { outputPath = rest[index] }
        default:
            break
        }
        index += 1
    }
    runTap(seconds: seconds, outputPath: outputPath)
default:
    print("unknown command: \(command)")
    exit(1)
}
