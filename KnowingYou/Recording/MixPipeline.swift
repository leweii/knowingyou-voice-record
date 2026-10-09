import AVFoundation

/// The testable core of `RecordingSession`'s mixing: takes both sources'
/// capture buffers (any sample rate / layout) stamped with the hardware time
/// of their first sample, and hands back equal-length, time-aligned 48kHz
/// mono mic/system chunks for the mixer. Kept free of actors, timers and
/// devices so `RecordingSimulationTests` can drive the exact production code
/// with simulated devices on a virtual clock.
///
/// How it stays click-free (2026-10-09 rewrite — the previous "drain a fixed
/// amount / mix what both have" scheme produced a click at every buffer
/// boundary of a misread system stream and could zero-pad mid-stream):
/// - One output timeline in host-clock seconds. Each pass emits audio up to
///   the newest moment *every live source* has delivered, so ordinary
///   callback jitter just waits instead of becoming silence.
/// - Each source's samples are placed on that timeline by their hardware
///   timestamps. Small timing error (clock drift between the mic and the
///   output device, tens of ppm) is absorbed by a resampler whose ratio is
///   nudged by at most `maxDriftCorrection` — inaudible. Only a real
///   discontinuity (> `realignThreshold`) jumps: silence for a genuine gap,
///   dropping audio that arrived too late to be used.
/// - A source that delivered nothing for `stallTimeout` (tap still starting,
///   device switching) stops holding the other one back; it's silent until
///   it comes back, then lines up again by timestamp.
final class MixPipeline: @unchecked Sendable {
    struct Chunk {
        var mic: [Float]
        var system: [Float]
        var count: Int { mic.count }
    }

    static let sampleRate = 48000.0
    static let stallTimeout: TimeInterval = 0.3
    static let realignThreshold: TimeInterval = 0.02
    static let maxDriftCorrection = 0.001 // ±1000 ppm, i.e. ±0.1% speed
    /// How quickly drift correction reacts: a steady error of this many
    /// seconds' worth of `driftResponseTime` → full correction.
    static let driftResponseTime: TimeInterval = 2.0

    private let mic = Source()
    private let system = Source()
    /// False when system audio is off or its tap failed to start.
    var hasSystemSource: Bool

    /// Host-clock time of the next output sample; nil until the first audio.
    private var timeline: TimeInterval?
    private var firstPumpTime: TimeInterval?

    init(hasSystemSource: Bool) {
        self.hasSystemSource = hasSystemSource
    }

    /// Realtime audio thread. `startTime`: host-clock seconds of the
    /// buffer's first sample. `arrival`: host-clock seconds now.
    func ingestMic(_ buffer: AVAudioPCMBuffer, startTime: TimeInterval, arrival: TimeInterval) {
        mic.queue.enqueue(buffer, startTime: startTime, arrival: arrival)
    }

    /// Realtime audio thread. See `ingestMic`.
    func ingestSystem(_ buffer: AVAudioPCMBuffer, startTime: TimeInterval, arrival: TimeInterval) {
        system.queue.enqueue(buffer, startTime: startTime, arrival: arrival)
    }

    /// Emits everything that's ready as of `now`; `flush` (on stop) emits
    /// everything that's left, padding the source that ends first.
    func pump(now: TimeInterval, flush: Bool = false) -> Chunk {
        if firstPumpTime == nil { firstPumpTime = now }
        let sources = hasSystemSource ? [mic, system] : [mic]
        let snapshots = sources.map { $0.queue.snapshot() }

        if timeline == nil {
            let starts = snapshots.filter { $0.count > 0 }.map { $0.endTime - Double($0.count) / Self.sampleRate }
            guard let earliest = starts.min() else { return Chunk(mic: [], system: []) }
            timeline = earliest
        }
        guard let start = timeline else { return Chunk(mic: [], system: []) }

        // Line each source up against the timeline, then emit as much as
        // every live source can actually supply — so nothing is ever cut
        // short and padded with silence mid-stream.
        let capacities = sources.map { $0.prepare(timeline: start) }
        let liveCapacities = zip(capacities, snapshots).filter { !isStalled($0.1, now: now) }.map(\.0)
        let count: Int
        if flush {
            count = capacities.max() ?? 0
        } else {
            guard let smallest = liveCapacities.min() else { return Chunk(mic: [], system: []) }
            count = smallest
        }
        guard count > 0 else { return Chunk(mic: [], system: []) }

        let micOut = mic.render(count: count, flush: flush)
        let systemOut = hasSystemSource ? system.render(count: count, flush: flush) : [Float](repeating: 0, count: count)
        timeline = start + Double(count) / Self.sampleRate
        return Chunk(mic: micOut, system: systemOut)
    }

    private func isStalled(_ snapshot: SourceSampleQueue.Snapshot, now: TimeInterval) -> Bool {
        if let lastArrival = snapshot.lastArrival {
            return now - lastArrival > Self.stallTimeout
        }
        return now - (firstPumpTime ?? now) > Self.stallTimeout
    }
}

/// One input stream's pump-side state: its queue plus the drift-correcting
/// resampler that reads from it. Only `queue.enqueue` runs on the audio
/// thread; everything else runs on the pump.
private final class Source {
    let queue = SourceSampleQueue(targetSampleRate: MixPipeline.sampleRate)
    private var ratio = 1.0
    private var smoothedError = 0.0
    /// Fractional read position into the queue's first sample.
    private var fraction = 0.0
    /// The last sample consumed — the interpolator's left neighbour.
    private var previous: Float = 0

    /// Silence owed before this source's next sample (a real gap).
    private var pendingGap = 0
    /// Set while this source has no audio queued (not started yet, or ran
    /// dry during a stall): when audio arrives again it's placed exactly by
    /// timestamp, rather than eased in by drift correction.
    private var needsExactAlignment = true

    /// Lines this source up against the output timeline (drop late audio,
    /// note a gap, or nudge the drift-correction ratio) and returns how many
    /// output samples it can supply right now.
    func prepare(timeline: TimeInterval) -> Int {
        let rate = MixPipeline.sampleRate
        pendingGap = 0
        var snapshot = queue.snapshot()
        guard snapshot.count > 0 else {
            needsExactAlignment = true
            return 0
        }
        let nextTime = snapshot.endTime - (Double(snapshot.count) - fraction) / rate
        let error = nextTime - timeline
        let threshold = needsExactAlignment ? 0.5 / rate : MixPipeline.realignThreshold
        needsExactAlignment = false
        if error < -threshold {
            // Arrived too late to be used (e.g. a thread stall longer than the
            // stall timeout, after which the timeline moved on without it).
            queue.drop(min(snapshot.count, Int((-error * rate).rounded())))
            fraction = 0
            smoothedError = 0
            snapshot = queue.snapshot()
        } else if error > threshold {
            // A real gap before this source's next sample: silence.
            pendingGap = Int((error * rate).rounded())
            smoothedError = 0
        } else {
            // Small, slowly varying error: clock drift. Nudge the read speed
            // so it converges to zero.
            smoothedError += 0.1 * (error - smoothedError)
            let correction = max(-MixPipeline.maxDriftCorrection, min(MixPipeline.maxDriftCorrection, smoothedError / MixPipeline.driftResponseTime))
            ratio = 1 - correction
        }
        // Catmull-Rom reads two samples ahead of the read position.
        let readable = max(0, Int((Double(snapshot.count) - fraction - 3) / ratio))
        return pendingGap + readable
    }

    /// `count` samples for the span `prepare` was called for; silence for
    /// whatever this source can't supply (stalled, or end of recording).
    func render(count: Int, flush: Bool) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(count)
        let gap = min(count, pendingGap)
        out.append(contentsOf: repeatElement(0, count: gap))
        pendingGap -= gap

        let wanted = count - out.count
        if wanted > 0 {
            let samples = queue.peekAll()
            var produced = 0
            var position = fraction
            while produced < wanted {
                let i = Int(position)
                guard i + 2 < samples.count || (flush && i < samples.count) else { break }
                let t = Float(position - Double(i))
                let y0 = i > 0 ? samples[i - 1] : previous
                let y1 = samples[i]
                let y2 = i + 1 < samples.count ? samples[i + 1] : y1
                let y3 = i + 2 < samples.count ? samples[i + 2] : y2
                out.append(t == 0 ? y1 : Self.catmullRom(y0, y1, y2, y3, t))
                produced += 1
                position += ratio
            }
            let consumed = min(Int(position), samples.count)
            if consumed > 0 { previous = samples[consumed - 1] }
            fraction = consumed == samples.count ? 0 : position - Double(consumed)
            queue.drop(consumed)
            if out.count < count {
                out.append(contentsOf: repeatElement(0, count: count - out.count))
            }
        }
        return out
    }

    private static func catmullRom(_ y0: Float, _ y1: Float, _ y2: Float, _ y3: Float, _ t: Float) -> Float {
        let a = -0.5 * y0 + 1.5 * y1 - 1.5 * y2 + 0.5 * y3
        let b = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
        let c = -0.5 * y0 + 0.5 * y2
        return ((a * t + b) * t + c) * t + y1
    }
}

/// Thread-safe holding pen for one source's mono Float samples at
/// `targetSampleRate`, plus the host-clock time just after the newest sample.
/// `enqueue` runs on a realtime audio thread: it downmixes (handling both
/// planar and interleaved buffers), resamples if the device isn't at 48kHz,
/// and appends (real allocations — not gold-standard realtime-safe, but the
/// pragmatic v1 tradeoff; see decision record). Each queue is fed by exactly
/// one source's callback, so the converter state needs no lock.
final class SourceSampleQueue: @unchecked Sendable {
    struct Snapshot {
        var count: Int
        var endTime: TimeInterval
        var lastArrival: TimeInterval?
    }

    /// Gaps in a source's timestamps longer than this are filled with
    /// silence so the queue stays contiguous in time; shorter ones are
    /// timestamp noise. Longer than `maxFilledGap`, the old audio is dropped
    /// and the queue restarts at the new timestamp.
    static let minFilledGap: TimeInterval = 0.02
    static let maxFilledGap: TimeInterval = 5

    private let lock = NSLock()
    private var samples: [Float] = []
    private var endTime: TimeInterval = 0
    private var lastArrival: TimeInterval?
    private let targetSampleRate: Double
    private var converter: AVAudioConverter?
    private var converterInputRate: Double = 0

    init(targetSampleRate: Double) {
        self.targetSampleRate = targetSampleRate
    }

    func enqueue(_ buffer: AVAudioPCMBuffer, startTime: TimeInterval, arrival: TimeInterval) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frameLength)
        if buffer.format.isInterleaved {
            // One block of L R L R …: `floatChannelData[c]` points at
            // channel c's first sample and successive frames are `stride`
            // apart. Reading it as planar (index by frame) was the cause of
            // the 2026-10-09 "noise while others talk" recordings — half of
            // every system-audio buffer misread, a click every 512 samples.
            let data = channelData[0]
            let stride = buffer.stride
            for frame in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount { sum += data[frame * stride + channel] }
                mono[frame] = sum
            }
        } else {
            for channel in 0..<channelCount {
                let channelSamples = channelData[channel]
                for frame in 0..<frameLength { mono[frame] += channelSamples[frame] }
            }
        }
        if channelCount > 1 {
            let scale = Float(1) / Float(channelCount)
            for frame in 0..<frameLength { mono[frame] *= scale }
        }

        let sampleRate = buffer.format.sampleRate
        if sampleRate != targetSampleRate {
            // Written as if it were 48kHz, a 44.1/24/16kHz stream plays at
            // the wrong speed and pitch.
            guard let resampled = resample(mono, from: sampleRate) else { return }
            mono = resampled
        }
        let bufferEnd = startTime + Double(frameLength) / sampleRate

        lock.lock()
        if samples.isEmpty {
            endTime = startTime
        } else {
            let gap = startTime - endTime
            if gap > Self.maxFilledGap || gap < -Self.maxFilledGap {
                samples.removeAll()
            } else if gap > Self.minFilledGap {
                samples.append(contentsOf: repeatElement(0, count: Int((gap * targetSampleRate).rounded())))
            }
        }
        samples.append(contentsOf: mono)
        endTime = bufferEnd
        lastArrival = arrival
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(count: samples.count, endTime: endTime, lastArrival: lastArrival)
    }

    func peekAll() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func drop(_ count: Int) {
        guard count > 0 else { return }
        lock.lock()
        samples.removeFirst(min(count, samples.count))
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
}
