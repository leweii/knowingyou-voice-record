import AVFoundation
import AudioToolbox
import CoreAudio

/// Records the whole system's audio output, excluding this app's own
/// process, via a Core Audio Process Tap + private aggregate device (see
/// `ProcessTap`). Also exposes `probePermission()` for `Permissions`.
final class SystemAudioTap: @unchecked Sendable {
    enum Event: Sendable {
        case started(format: AVAudioFormat)
        case outputDeviceChanged
        case stopped
        case failed(KYError)
    }

    /// Realtime-thread callback: no `print`, no locks, no actor hops.
    var onBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    private let eventContinuation: AsyncStream<Event>.Continuation
    let events: AsyncStream<Event>

    private var processTap: ProcessTap?
    private var ioProcID: AudioDeviceIOProcID?
    private var avFormat: AVAudioFormat?
    private var outputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var isRunning = false

    init() {
        var continuation: AsyncStream<Event>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    func start() throws {
        try startInternal()
        isRunning = true
        startListeningForOutputDeviceChanges()
        eventContinuation.yield(.started(format: avFormat!))
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopListeningForOutputDeviceChanges()
        stopInternal()
        eventContinuation.yield(.stopped)
    }

    /// Attempts the full pipeline (tap → aggregate device → IOProc →
    /// `AudioDeviceStart`) and immediately tears it down. Per the S06 spike,
    /// tap *creation* alone returns `noErr` even without real permission —
    /// `AudioDeviceStart` is the call that actually needs "系统音频录制".
    static func probePermission() async -> PermissionStatus {
        let tap = ProcessTap()
        do {
            try tap.activate()
        } catch {
            tap.invalidate()
            return .notDetermined
        }

        var probeIOProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&probeIOProcID, tap.aggregateDeviceID, nil) { _, _, _, _, _ in }
        guard ioStatus == noErr, let probeIOProcID else {
            tap.invalidate()
            return .denied
        }

        let startStatus = AudioDeviceStart(tap.aggregateDeviceID, probeIOProcID)
        AudioDeviceStop(tap.aggregateDeviceID, probeIOProcID)
        AudioDeviceDestroyIOProcID(tap.aggregateDeviceID, probeIOProcID)
        tap.invalidate()
        return startStatus == noErr ? .granted : .denied
    }

    // MARK: - Internals (no event emission — shared by start()/stop() and the
    // output-device-change restart, which emits exactly one `.outputDeviceChanged`
    // rather than a stop+start pair of events)

    private func startInternal() throws {
        let tap = ProcessTap()
        try tap.activate()

        guard var asbd = tap.format, let format = AVAudioFormat(streamDescription: &asbd) else {
            tap.invalidate()
            throw KYError.systemAudioTapFailed(kAudio_ParamError)
        }

        var newIOProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, tap.aggregateDeviceID, nil) { [weak self] _, inputData, _, _, _ in
            guard let self, let format = self.avFormat else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else { return }
            let time = AVAudioTime(hostTime: mach_absolute_time())
            self.onBuffer?(buffer, time)
        }
        guard ioStatus == noErr, let newIOProcID else {
            tap.invalidate()
            throw KYError.systemAudioTapFailed(ioStatus)
        }

        let startStatus = AudioDeviceStart(tap.aggregateDeviceID, newIOProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(tap.aggregateDeviceID, newIOProcID)
            tap.invalidate()
            throw KYError.systemAudioTapFailed(startStatus)
        }

        processTap = tap
        ioProcID = newIOProcID
        avFormat = format
    }

    private func stopInternal() {
        if let tap = processTap, let ioProcID {
            AudioDeviceStop(tap.aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(tap.aggregateDeviceID, ioProcID)
        }
        processTap?.invalidate()
        processTap = nil
        ioProcID = nil
        avFormat = nil
    }

    // MARK: - Output device change handling

    private func startListeningForOutputDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleOutputDeviceChanged()
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        outputDeviceListenerBlock = block
    }

    private func stopListeningForOutputDeviceChanges() {
        guard let block = outputDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        outputDeviceListenerBlock = nil
    }

    /// The aggregate device's main sub-device is fixed to an output UID at
    /// creation time, so a device switch means tearing down and rebuilding
    /// the whole pipeline (tap included) rather than swapping just the
    /// aggregate device. Simpler than the "reuse the tap" approach sketched
    /// in the spec, at the cost of a slightly longer gap; see decision record.
    private func handleOutputDeviceChanged() {
        guard isRunning else { return }
        stopInternal()
        do {
            try startInternal()
            eventContinuation.yield(.outputDeviceChanged)
        } catch let error as KYError {
            isRunning = false
            eventContinuation.yield(.failed(error))
        } catch {
            isRunning = false
            eventContinuation.yield(.failed(.systemAudioTapFailed(kAudio_ParamError)))
        }
    }
}
