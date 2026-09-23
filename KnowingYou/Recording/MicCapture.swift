import AVFoundation
import AudioToolbox
import CoreAudio

/// Microphone capture via `AVAudioEngine`, following either the system
/// default input device (`.smart`) or a pinned device by UID. Falls back to
/// the default automatically if a pinned device disappears (unplugged) —
/// `AVAudioEngineConfigurationChange` fires either way and we just rebuild
/// the tap against whatever the engine now considers the input.
final class MicCapture: @unchecked Sendable {
    struct Config: Sendable {
        var selection: MicSelection
    }

    enum Event: Sendable {
        case started(deviceName: String)
        case deviceChanged(to: String)
        case stopped
        case failed(KYError)
    }

    private let config: Config
    private let engine = AVAudioEngine()
    private let eventContinuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var configChangeObserver: NSObjectProtocol?
    private var isRunning = false

    /// Realtime-thread callback: no `print`, no locks, no actor hops — just
    /// forward the buffer. `AVAudioTime.hostTime` lets S09 align the two streams.
    var onBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    var format: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    init(config: Config) {
        self.config = config
        var continuation: AsyncStream<Event>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation

        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    func start() throws {
        try selectDevice(for: config.selection)
        installTap()
        do {
            try engine.start()
        } catch {
            throw KYError.audioDeviceUnavailable("AVAudioEngine.start failed: \(error)")
        }
        isRunning = true
        if config.selection == .smart {
            startListeningForDefaultDeviceChanges()
        }
        eventContinuation.yield(.started(deviceName: currentDeviceName() ?? "unknown"))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        stopListeningForDefaultDeviceChanges()
        eventContinuation.yield(.stopped)
    }

    private func installTap() {
        let tapFormat = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, time in
            self?.onBuffer?(buffer, time)
        }
    }

    private func selectDevice(for selection: MicSelection) throws {
        switch selection {
        case .smart:
            break // AVAudioEngine already follows the system default input.
        case .device(let uid):
            guard let deviceID = Self.deviceID(forUID: uid) else {
                throw KYError.audioDeviceUnavailable(uid)
            }
            try setInputDevice(deviceID)
        }
    }

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw KYError.audioDeviceUnavailable("input node has no audio unit")
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw KYError.audioDeviceUnavailable("AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice) failed: \(status)")
        }
    }

    /// Fires for both explicit engine reconfiguration (device unplugged,
    /// sample rate changed elsewhere) and — in `.smart` mode — the default
    /// input device changing. Either way the fix is the same: reinstall the
    /// tap against whatever the engine now reports as its input format.
    private func handleConfigurationChange() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        installTap()
        do {
            try engine.start()
            eventContinuation.yield(.deviceChanged(to: currentDeviceName() ?? "unknown"))
        } catch {
            eventContinuation.yield(.failed(.audioDeviceUnavailable("restart after configuration change failed: \(error)")))
        }
    }

    private func currentDeviceName() -> String? {
        let deviceID: AudioDeviceID?
        switch config.selection {
        case .smart:
            deviceID = Self.defaultInputDeviceID()
        case .device(let uid):
            deviceID = Self.deviceID(forUID: uid) ?? Self.defaultInputDeviceID()
        }
        guard let deviceID else { return nil }
        return AudioDevices.name(for: deviceID)
    }

    // MARK: - Default device change listening (.smart mode only)

    private func startListeningForDefaultDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleConfigurationChange()
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        defaultDeviceListenerBlock = block
    }

    private func stopListeningForDefaultDeviceChanges() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        defaultDeviceListenerBlock = nil
    }

    // MARK: - Device lookup helpers

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        AudioDevices.allDeviceIDs()?.first { AudioDevices.uid(for: $0) == uid }
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { return nil }
        return deviceID
    }
}
