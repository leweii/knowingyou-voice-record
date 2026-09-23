import CoreAudio
import Foundation

/// Continuously answers "which whitelisted apps are using the microphone
/// right now," as a diff'd event stream. No debouncing and no
/// idle/recording state machine here — that's S13's `MeetingCoordinator`,
/// built on top of `updates`.
actor MeetingDetector {
    struct ActiveMicUser: Sendable, Equatable {
        let app: KnownApp
        let pids: [pid_t]
        let bundleIDs: [String]
    }

    private let apps: @Sendable () -> [KnownApp]
    private let reader: ProcessObjectReading
    private let pollInterval: Duration

    private let updatesContinuation: AsyncStream<[ActiveMicUser]>.Continuation
    nonisolated let updates: AsyncStream<[ActiveMicUser]>

    private var lastSnapshot: [ActiveMicUser] = []
    private var pollTask: Task<Void, Never>?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListenerIDs: [AudioObjectID] = []
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?

    init(
        apps: @escaping @Sendable () -> [KnownApp],
        reader: ProcessObjectReading = CoreAudioProcessObjectReader(),
        pollInterval: Duration = .seconds(2)
    ) {
        self.apps = apps
        self.reader = reader
        self.pollInterval = pollInterval
        var continuation: AsyncStream<[ActiveMicUser]>.Continuation!
        self.updates = AsyncStream { continuation = $0 }
        self.updatesContinuation = continuation
    }

    func start() async {
        guard pollTask == nil else { return }
        installSystemLevelListeners()
        installDeviceLevelListeners()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop() async {
        pollTask?.cancel()
        pollTask = nil
        removeSystemLevelListeners()
        removeDeviceLevelListeners()
    }

    /// Polls immediately and returns the result — used by S13 for manual
    /// "start recording right now" to pick a source-app name without waiting
    /// for the next scheduled poll tick.
    func snapshot() async -> [ActiveMicUser] {
        poll()
        return lastSnapshot
    }

    @discardableResult
    private func poll() -> [ActiveMicUser] {
        let enabledApps = apps().filter(\.isEnabled)
        let processes = reader.activeInputProcesses()

        var grouped: [String: (app: KnownApp, pids: [pid_t], bundleIDs: [String])] = [:]
        for (pid, bundleID) in processes {
            guard let match = KnownApps.match(bundleID: bundleID, in: enabledApps) else { continue }
            var entry = grouped[match.bundleIDPrefix] ?? (match, [], [])
            entry.pids.append(pid)
            entry.bundleIDs.append(bundleID)
            grouped[match.bundleIDPrefix] = entry
        }

        let newSnapshot = grouped.values
            .map { ActiveMicUser(app: $0.app, pids: $0.pids.sorted(), bundleIDs: $0.bundleIDs.sorted()) }
            .sorted { $0.app.bundleIDPrefix < $1.app.bundleIDPrefix }

        guard newSnapshot != lastSnapshot else { return lastSnapshot }
        lastSnapshot = newSnapshot
        updatesContinuation.yield(newSnapshot)
        return newSnapshot
    }

    // MARK: - Listeners (latency-tightening only; the 2s poll above is what
    // actually guarantees detection — see this spec's decision record for
    // why macOS 26's process-level notification can't be trusted alone)

    private func installSystemLevelListeners() {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let deviceListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            Task { await self.handleDeviceListChanged() }
        }
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, DispatchQueue.global(), deviceListListener)
        deviceListListenerBlock = deviceListListener

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultInputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            Task { await self.pollFromListener() }
        }
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultInputAddress, DispatchQueue.global(), defaultInputListener)
        defaultInputListenerBlock = defaultInputListener
    }

    private func removeSystemLevelListeners() {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        if let block = deviceListListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, DispatchQueue.global(), block)
            deviceListListenerBlock = nil
        }
        if let block = defaultInputListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, DispatchQueue.global(), block)
            defaultInputListenerBlock = nil
        }
    }

    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` on every current device
    /// (not just input-capable ones — matching the S06 spike tool exactly;
    /// listening on a few extra output-only devices is harmless, just an
    /// occasional redundant poll trigger, and avoids reimplementing stream-
    /// direction inspection for no real benefit).
    private func installDeviceLevelListeners() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            Task { await self.pollFromListener() }
        }
        deviceListenerBlock = listener

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for deviceID in Self.allDeviceIDs() {
            AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.global(), listener)
        }
        deviceListenerIDs = Self.allDeviceIDs()
    }

    private func removeDeviceLevelListeners() {
        guard let listener = deviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for deviceID in deviceListenerIDs {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.global(), listener)
        }
        deviceListenerBlock = nil
        deviceListenerIDs = []
    }

    private func handleDeviceListChanged() {
        removeDeviceLevelListeners()
        installDeviceLevelListeners()
        poll()
    }

    private func pollFromListener() {
        guard pollTask != nil else { return } // ignore stray callbacks after stop()
        poll()
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }
}
