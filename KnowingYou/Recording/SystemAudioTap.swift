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
    private var sampleRateListenerBlock: AudioObjectPropertyListenerBlock?
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

    /// The format of the buffers the IOProc actually delivers. The tap's own
    /// format always says 48kHz, but the aggregate device — and so every
    /// buffer it hands the IOProc — runs at its main sub-device's rate: the
    /// output device's, e.g. 44.1kHz (measured 2026-10-09: ~86 × 512-frame
    /// callbacks/s on built-in speakers set to 44.1kHz). Labelling those
    /// 44.1kHz samples 48kHz played system audio 8.8% fast and starved the
    /// mixer. Channel count and interleaving do come from the tap (it's
    /// interleaved stereo Float32).
    static func captureFormat(tapFormat: AudioStreamBasicDescription, aggregateNominalSampleRate: Double?) -> AVAudioFormat? {
        let isFloat = tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0
        guard tapFormat.mFormatID == kAudioFormatLinearPCM, isFloat, tapFormat.mBitsPerChannel == 32,
              tapFormat.mChannelsPerFrame > 0 else { return nil }
        let rate = aggregateNominalSampleRate ?? tapFormat.mSampleRate
        let interleaved = tapFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: tapFormat.mChannelsPerFrame, interleaved: interleaved)
    }

    // MARK: - Internals (no event emission — shared by start()/stop() and the
    // output-device-change restart, which emits exactly one `.outputDeviceChanged`
    // rather than a stop+start pair of events)

    private func startInternal() throws {
        let tap = ProcessTap()
        try tap.activate()

        guard let asbd = tap.format,
              let format = Self.captureFormat(tapFormat: asbd, aggregateNominalSampleRate: CoreAudioUtils.nominalSampleRate(tap.aggregateDeviceID))
        else {
            tap.invalidate()
            throw KYError.systemAudioTapFailed(kAudio_ParamError)
        }

        var newIOProcID: AudioDeviceIOProcID?
        // `format` is captured by value: the IOProc runs on Core Audio's
        // realtime thread, and the main thread replaces `avFormat` on rebuild.
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, tap.aggregateDeviceID, nil) { [weak self] _, inputData, inputTime, _, _ in
            guard let self, let onBuffer = self.onBuffer else { return }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else { return }
            // The hardware timestamp of the buffer's first sample — what the
            // mixer aligns the two sources by. (Reading the clock here instead
            // would add the callback's scheduling jitter.)
            let hostTime = inputTime.pointee.mFlags.contains(.hostTimeValid) ? inputTime.pointee.mHostTime : mach_absolute_time()
            onBuffer(buffer, AVAudioTime(hostTime: hostTime))
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
        startListeningForSampleRateChanges(of: tap.aggregateDeviceID)
    }

    private func stopInternal() {
        if let tap = processTap { stopListeningForSampleRateChanges(of: tap.aggregateDeviceID) }
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

    /// `captureFormat` labels buffers with the aggregate device's rate at
    /// start; if the output device changes rate mid-recording (Audio MIDI
    /// Setup, a Bluetooth headset switching profiles), rebuild so the label
    /// stays true.
    private func startListeningForSampleRateChanges(of deviceID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let labelledRate = avFormat?.sampleRate
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, CoreAudioUtils.nominalSampleRate(deviceID) != labelledRate else { return }
            self.handleOutputDeviceChanged()
        }
        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        sampleRateListenerBlock = block
    }

    private func stopListeningForSampleRateChanges(of deviceID: AudioObjectID) {
        guard let block = sampleRateListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        sampleRateListenerBlock = nil
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
