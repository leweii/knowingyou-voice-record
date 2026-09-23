import AudioToolbox
import CoreAudio
import Foundation

/// Owns the Core Audio Process Tap + its private aggregate device pairing.
/// `SystemAudioTap` (higher level) drives the IOProc and buffer delivery;
/// this type just owns creation/teardown of the two Core Audio objects, in
/// the order documented in docs/spikes/2026-09-23-process-tap-spike.md
/// (that spike is where this exact sequence was empirically verified to
/// actually capture real audio, not just compile).
final class ProcessTap: @unchecked Sendable {
    private(set) var tapID = AudioObjectID(kAudioObjectUnknown)
    private(set) var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private(set) var format: AudioStreamBasicDescription?

    func activate() throws {
        guard let ownProcessObjectID = CoreAudioUtils.ownProcessObjectID() else {
            throw KYError.systemAudioTapFailed(kAudioHardwareUnspecifiedError)
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObjectID])
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let createStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard createStatus == noErr else {
            throw KYError.systemAudioTapFailed(createStatus)
        }
        tapID = newTapID

        guard let outputDeviceID = CoreAudioUtils.defaultOutputDeviceID(),
              let outputUID = CoreAudioUtils.deviceUID(outputDeviceID) else {
            invalidate()
            throw KYError.audioDeviceUnavailable("no default output device")
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "KnowingYou-SystemAudioTap",
            kAudioAggregateDeviceUIDKey: "com.jakobhe.knowingyou.systemaudiotap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
        ]

        var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateDeviceID)
        guard aggregateStatus == noErr else {
            invalidate()
            throw KYError.systemAudioTapFailed(aggregateStatus)
        }
        aggregateDeviceID = newAggregateDeviceID
        format = CoreAudioUtils.tapFormat(tapID)
    }

    /// Idempotent, safe to call even if `activate()` partially failed.
    func invalidate() {
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit {
        invalidate()
    }
}
