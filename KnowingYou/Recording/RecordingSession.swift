import AVFoundation

/// Orchestrates `MicCapture` + `SystemAudioTap` into one mixed 48kHz mono/
/// stereo recording, written crash-safe to `.caf` and transcoded to `.m4a`
/// on stop. See this spec's decision record for the simplified (non-sample-
/// accurate) alignment strategy this uses.
actor RecordingSession {
    struct Config: Sendable {
        var info: RecordingInfo
        var mic: MicSelection
        var captureSystemAudio: Bool
        var format: AudioFormat
    }

    enum Event: Sendable {
        case state(RecordingSessionState)
        case level(mic: Float, system: Float)
        case elapsed(TimeInterval)
        case deviceEvent(String)
        case error(KYError)
    }

    private static let targetSampleRate = 48000.0
    /// How far one source may run ahead of a stalled other before the
    /// stalled one is zero-padded — see `Mixer.framesToMix`.
    private static let maxSourceLag = 24000 // 500ms @ 48kHz

    private let config: Config
    private let eventContinuation: AsyncStream<Event>.Continuation
    nonisolated let events: AsyncStream<Event>

    private var micCapture: MicCapture?
    private var systemAudioTap: SystemAudioTap?
    private let micQueue = SourceSampleQueue(targetSampleRate: targetSampleRate)
    private let systemQueue = SourceSampleQueue(targetSampleRate: targetSampleRate)

    private var writer: AVAudioFile?
    private var state: RecordingSessionState = .preparing {
        didSet { eventContinuation.yield(.state(state)) }
    }

    private(set) var pausedIntervals: [ClosedRange<Date>] = []
    private var isPaused = false
    private var currentPauseStart: Date?

    private var startedAt: Date?
    private var pumpTask: Task<Void, Never>?
    private var micEventTask: Task<Void, Never>?
    private var systemEventTask: Task<Void, Never>?
    private var micLevelSmoother = LevelSmoother()
    private var systemLevelSmoother = LevelSmoother()
    private var ticksSinceLastElapsedEvent = 0
    /// S20 edge case #3 (disk full): a handful of consecutive write
    /// failures (as opposed to one transient blip) means the volume is
    /// probably actually full/gone — stop trying rather than spin the pump
    /// loop forever re-failing the same write every 50ms.
    private var consecutiveWriteFailures = 0

    init(config: Config) {
        self.config = config
        var continuation: AsyncStream<Event>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    func start() async throws {
        guard Self.hasEnoughDiskSpace(at: config.info.directory) else {
            state = .failed(.diskFull)
            throw KYError.diskFull
        }
        guard FileManager.default.isWritableFile(atPath: config.info.directory.path) else {
            state = .failed(.saveDirectoryUnwritable(config.info.directory))
            throw KYError.saveDirectoryUnwritable(config.info.directory)
        }
        try? FileManager.default.createDirectory(at: config.info.directory, withIntermediateDirectories: true)

        let channelCount: AVAudioChannelCount = config.format == .dualTrack ? 2 : 1
        guard let writerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw KYError.encodingFailed("could not construct writer format")
        }
        writer = try AVAudioFile(
            forWriting: config.info.cafURL,
            settings: writerFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let micQueue = micQueue
        let mic = MicCapture(config: .init(selection: config.mic))
        mic.onBuffer = { buffer, time in
            micQueue.enqueue(buffer, hostTime: time.hostTime)
        }
        do {
            try mic.start()
        } catch {
            state = .failed(.audioDeviceUnavailable("mic: \(error)"))
            throw error
        }
        micCapture = mic
        micEventTask = Task { [weak self] in
            for await event in mic.events {
                await self?.handleMicEvent(event)
            }
        }

        if config.captureSystemAudio {
            let systemQueue = systemQueue
            let tap = SystemAudioTap()
            tap.onBuffer = { buffer, time in
                systemQueue.enqueue(buffer, hostTime: time.hostTime)
            }
            do {
                try tap.start()
                systemAudioTap = tap
                systemEventTask = Task { [weak self] in
                    for await event in tap.events {
                        await self?.handleSystemEvent(event)
                    }
                }
            } catch {
                // System audio is a nice-to-have on top of the mic, not a
                // hard requirement — if the tap can't start (permission
                // revoked mid-session, macOS's Process Tap throttle, etc.),
                // fall back to mic-only instead of aborting the whole
                // recording (S20 edge case #11). The mic is already running
                // at this point, so we just surface the failure as an event
                // and keep going.
                eventContinuation.yield(.error(.systemAudioTapFailed(0)))
            }
        }

        startedAt = .now
        state = .recording
        startPumpLoop()
    }

    func pause() async {
        guard state == .recording else { return }
        isPaused = true
        currentPauseStart = .now
        state = .paused
    }

    func resume() async {
        guard isPaused else { return }
        isPaused = false
        if let pauseStart = currentPauseStart {
            pausedIntervals.append(pauseStart...Date.now)
            currentPauseStart = nil
        }
        state = .recording
    }

    @discardableResult
    func stop() async throws -> URL {
        pumpTask?.cancel()
        pumpTask = nil
        micEventTask?.cancel()
        systemEventTask?.cancel()
        micEventTask = nil
        systemEventTask = nil

        micCapture?.stop()
        systemAudioTap?.stop()
        pumpOnce(flush: true) // the tail both sources delivered since the last tick
        micCapture = nil
        systemAudioTap = nil

        state = .stopping
        let cafURL = config.info.cafURL
        writer = nil // AVAudioFile finalizes/closes on deinit

        do {
            try await Encoder.encode(caf: cafURL, to: config.info.audioURL, format: config.format)
            try? FileManager.default.removeItem(at: cafURL)
            state = .finished(config.info.audioURL)
            return config.info.audioURL
        } catch {
            // Leave the CAF in place — RecordingStore's crash recovery can
            // pick it up later.
            let mappedError = KYError.encodingFailed("\(error)")
            state = .failed(mappedError)
            throw mappedError
        }
    }

    // MARK: - Mixing pump

    private func startPumpLoop() {
        pumpTask = Task { [weak self] in
            // Fixed deadlines rather than "sleep 50ms after each pass": that
            // always runs slightly slower than the sources produce audio, so
            // the queues grow without bound and the level meter (measured on
            // the drained chunk) falls further behind the real sound the
            // longer a recording runs (Jakob, 2026-09-30: "波形图不够实时").
            let clock = ContinuousClock()
            var next = clock.now
            while !Task.isCancelled {
                guard let self else { return }
                await self.pumpOnce()
                next += .milliseconds(50)
                if next < clock.now { next = clock.now } // stalled: resume the cadence, don't burst forever
                try? await Task.sleep(until: next, tolerance: .zero, clock: clock)
            }
        }
    }

    /// Mixes whatever both sources have delivered since the last pass (see
    /// `Mixer.framesToMix`), and writes it out unless paused. Not
    /// sample-accurate hostTime alignment — the sources are assumed to start
    /// together and run at the same 48kHz rate once resampled — which is the
    /// pragmatic v1 tradeoff (see decision record). `flush` drains
    /// everything left, padding the shorter source; used on stop.
    private func pumpOnce(flush: Bool = false) {
        let hasSystemSource = config.captureSystemAudio && systemAudioTap != nil
        let count = Mixer.framesToMix(
            micAvailable: micQueue.availableCount,
            systemAvailable: hasSystemSource ? systemQueue.availableCount : nil,
            maxLag: Self.maxSourceLag,
            flush: flush
        )
        let micChunk = micQueue.drain(count: count)
        let systemChunk = hasSystemSource
            ? systemQueue.drain(count: count)
            : [Float](repeating: 0, count: count)

        // An empty pass (nothing new from a source yet) keeps the meter where
        // it is instead of dipping it to silence for a tick.
        let rawMicRMS = LevelMeter.rms(micChunk)
        var micLevel = micLevelSmoother.value
        if count > 0 {
            micLevel = micLevelSmoother.update(with: LevelMeter.normalizedLevel(fromRMS: rawMicRMS))
            let systemLevel = systemLevelSmoother.update(with: LevelMeter.normalizedLevel(fromRMS: LevelMeter.rms(systemChunk)))
            eventContinuation.yield(.level(mic: micLevel, system: systemLevel))
        }

        ticksSinceLastElapsedEvent += 1
        if ticksSinceLastElapsedEvent >= 20, let startedAt { // ~once/second
            ticksSinceLastElapsedEvent = 0
            eventContinuation.yield(.elapsed(Date.now.timeIntervalSince(startedAt)))
            // Jakob reported the pill's level meter never moves during a real
            // recording even while talking (2026-09-24) — a code review of
            // the whole level pipeline (RMS → dB normalization → smoother →
            // .level event → FloatingWidgetPanel.updateLevel) didn't turn up
            // a bug, and a direct-injection test of the UI half of that
            // pipeline worked fine, but none of this can be checked against
            // real microphone input in this environment (S07's decision
            // record — mic TCC is misattributed to the host process here).
            // This once-a-second log line is so the *next* real test gives
            // an actual number instead of another guess: if `rawMicRMS`
            // stays at 0.0 while he's talking, the bug is upstream in real
            // capture (wrong/muted input device, permission not really
            // active, etc.); if it's a small-but-nonzero number that never
            // visibly moves the bars, the bug is in this mapping after all.
            AppLog.recording.debug("level pipeline: rawMicRMS=\(rawMicRMS, privacy: .public) normalizedMicLevel=\(micLevel, privacy: .public)")
        }

        guard count > 0, !isPaused else { return }

        let mixedSamples: [Float]
        let channelCount: Int
        switch config.format {
        case .monoMix:
            mixedSamples = Mixer.monoMix(mic: micChunk, system: systemChunk)
            channelCount = 1
        case .dualTrack:
            mixedSamples = Mixer.dualTrack(mic: micChunk, system: systemChunk)
            channelCount = 2
        }

        guard let buffer = Self.makeBuffer(from: mixedSamples, channelCount: channelCount) else { return }
        do {
            try writer?.write(from: buffer)
            consecutiveWriteFailures = 0
        } catch {
            consecutiveWriteFailures += 1
            eventContinuation.yield(.error(.encodingFailed("write failed: \(error)")))
            if consecutiveWriteFailures >= 3 {
                // Likely the disk is actually full (or the volume vanished) —
                // stop the pump loop instead of re-failing the same write
                // every 50ms forever. `AppState` reacts to `.diskFull` by
                // stopping and finalizing whatever's already on disk.
                eventContinuation.yield(.error(.diskFull))
                pumpTask?.cancel()
            }
        }
    }

    private static func makeBuffer(from samples: [Float], channelCount: Int) -> AVAudioPCMBuffer? {
        guard channelCount > 0, samples.count % channelCount == 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: targetSampleRate,
                  channels: AVAudioChannelCount(channelCount),
                  interleaved: false
              ) else {
            return nil
        }
        let frameCount = samples.count / channelCount
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        guard let channelData = buffer.floatChannelData else { return nil }

        if channelCount == 1 {
            for frame in 0..<frameCount { channelData[0][frame] = samples[frame] }
        } else {
            for frame in 0..<frameCount {
                channelData[0][frame] = samples[frame * 2]
                channelData[1][frame] = samples[frame * 2 + 1]
            }
        }
        return buffer
    }

    // MARK: - Device events

    private func handleMicEvent(_ event: MicCapture.Event) {
        switch event {
        case .started(let name):
            eventContinuation.yield(.deviceEvent("麦克风：\(name)"))
        case .deviceChanged(let name):
            eventContinuation.yield(.deviceEvent("麦克风切换到 \(name)"))
        case .stopped:
            break
        case .failed(let error):
            eventContinuation.yield(.error(error))
        }
    }

    private func handleSystemEvent(_ event: SystemAudioTap.Event) {
        switch event {
        case .started:
            break
        case .outputDeviceChanged:
            eventContinuation.yield(.deviceEvent("系统音频输出设备已切换"))
        case .stopped:
            break
        case .failed(let error):
            eventContinuation.yield(.error(error))
        }
    }

    // MARK: - Disk space

    private static func hasEnoughDiskSpace(at directory: URL) -> Bool {
        guard let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true // fail open rather than block recording on an unrelated query failure
        }
        return available > 500_000_000
    }
}

/// Thread-safe holding pen for extracted mono Float samples from one audio
/// source, at `RecordingSession.targetSampleRate`. `enqueue` runs on a
/// realtime audio thread: it downmixes, resamples if the device isn't at
/// 48kHz, and appends (real allocations — not gold-standard realtime-safe,
/// but the pragmatic v1 tradeoff; see decision record). `drain` runs on the
/// actor. Each queue is fed by exactly one source's callback, so the
/// converter state needs no lock.
private final class SourceSampleQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private let targetSampleRate: Double
    private var converter: AVAudioConverter?
    private var converterInputRate: Double = 0

    init(targetSampleRate: Double) {
        self.targetSampleRate = targetSampleRate
    }

    func enqueue(_ buffer: AVAudioPCMBuffer, hostTime: UInt64) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frameLength)
        for channel in 0..<channelCount {
            let channelSamples = channelData[channel]
            for frame in 0..<frameLength {
                mono[frame] += channelSamples[frame]
            }
        }
        if channelCount > 1 {
            let scale = Float(1) / Float(channelCount)
            for frame in 0..<frameLength { mono[frame] *= scale }
        }

        let sampleRate = buffer.format.sampleRate
        if sampleRate != targetSampleRate {
            // Written as if it were 48kHz, a 44.1/24/16kHz device (Bluetooth
            // headsets, iPhone mic) plays back at the wrong speed and pitch,
            // and underruns the mix timeline.
            guard let resampled = resample(mono, from: sampleRate) else { return }
            mono = resampled
        }

        lock.lock()
        samples.append(contentsOf: mono)
        lock.unlock()
    }

    private func resample(_ input: [Float], from inputRate: Double) -> [Float]? {
        guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: inputRate, channels: 1),
              let outputFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1)
        else { return nil }
        if converter == nil || converterInputRate != inputRate {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converterInputRate = inputRate
        }
        guard let converter,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(input.count))
        else { return nil }
        inputBuffer.frameLength = AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer { inputBuffer.floatChannelData![0].update(from: $0.baseAddress!, count: input.count) }

        let capacity = AVAudioFrameCount(Double(input.count) * targetSampleRate / inputRate) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        // `.noDataNow` (not `.endOfStream`) keeps the converter's filter
        // state across buffers, so consecutive callbacks join seamlessly.
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, let data = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(outputBuffer.frameLength)))
    }

    var availableCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    /// Removes and returns up to `count` samples, zero-padding if fewer are
    /// available so the mixed timeline stays continuous across input gaps.
    func drain(count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if samples.count >= count {
            let result = Array(samples[0..<count])
            samples.removeFirst(count)
            return result
        } else {
            let result = Mixer.zeroPadded(samples, to: count)
            samples.removeAll()
            return result
        }
    }
}
