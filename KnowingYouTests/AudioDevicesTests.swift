import CoreAudio
import Testing
@testable import KnowingYou

struct AudioDevicesTests {
    @Test func enumeratesAtLeastOneInputDevice() {
        let devices = AudioDevices.currentInputDevices()
        #expect(!devices.isEmpty, "expected at least one input device (e.g. built-in microphone)")
    }

    @Test func everyDeviceHasNonEmptyUID() {
        for device in AudioDevices.currentInputDevices() {
            #expect(!device.uid.isEmpty)
            #expect(!device.name.isEmpty)
        }
    }

    @Test func builtInMicrophoneIsDetectedAsHavingInput() {
        guard let deviceIDs = AudioDevices.allDeviceIDs() else {
            Issue.record("could not enumerate any audio devices on this machine")
            return
        }
        let builtInMic = deviceIDs.first { deviceID in
            AudioDevices.name(for: deviceID)?.localizedCaseInsensitiveContains("MacBook") == true
                || AudioDevices.name(for: deviceID)?.localizedCaseInsensitiveContains("Built-in") == true
                || AudioDevices.name(for: deviceID)?.localizedCaseInsensitiveContains("内置") == true
        }
        // Not every test machine has a built-in mic (e.g. a Mac mini with none
        // connected) - only assert hasInputStreams when we actually found one.
        if let builtInMic {
            #expect(AudioDevices.hasInputStreams(builtInMic))
        }
    }

    @Test func deviceIDsAreUnique() {
        guard let deviceIDs = AudioDevices.allDeviceIDs() else { return }
        #expect(Set(deviceIDs).count == deviceIDs.count)
    }
}
