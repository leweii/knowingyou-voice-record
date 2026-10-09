import AVFoundation
import AudioToolbox
import Foundation
import Testing
@testable import KnowingYou

/// End-to-end simulation of a real meeting recording through the production
/// mixing code (`MixPipeline`, `SourceSampleQueue`, `SystemAudioTap.captureFormat`),
/// with simulated capture devices that behave the way the real ones were
/// measured to on a MacBook (2026-10-09):
///
/// - System audio (Process Tap → aggregate device): the tap *reports* 48kHz
///   interleaved stereo Float32, but the aggregate device runs at the output
///   device's rate — 44.1kHz on that machine — and the IOProc delivers
///   512-frame interleaved buffers at that rate (~86 callbacks/s).
/// - Microphone (AVAudioEngine tap): 48kHz mono, non-interleaved, ~100ms buffers.
/// - Independent clocks (tens of ppm drift), callback jitter, the tap starting
///   seconds after the mic (Process Tap creation can be slow), short thread
///   hiccups that deliver a backlog in a burst, a 50ms pump timer that
///   sometimes runs late, a tap rebuild after an output-device switch (with a
///   new sample rate), and a mic device switch.
///
/// Each source carries a pure tone, so any damage the pipeline does — a gap,
/// a misread buffer, a wrong sample rate — shows up as residual energy around
/// that tone, or as the wrong frequency. Jakob's 2026-10-09 recording
/// ("会议其他人说话的时候会有很多干扰的噪音") had a click every 512 samples.
struct RecordingSimulationTests {
    // MARK: - Scenarios

    @Test(arguments: [44100.0, 48000.0])
    func meetingWithRealisticDeviceBehaviourHasNoGlitches(outputDeviceRate: Double) throws {
        var scenario = Scenario.realisticMeeting
        scenario.system.segments[0].rate = outputDeviceRate
        var simulation = Simulation(scenario: scenario)
        let result = try simulation.run()

        let system = Analysis(samples: result.system, toneFrequency: Scenario.systemTone)
        let mic = Analysis(samples: result.mic, toneFrequency: Scenario.micTone)
        print("SIM rate=\(outputDeviceRate) system f=\(system.measuredFrequency) clean=\(system.cleanFraction) silent=\(system.silentSeconds)s glitches=\(Analysis.describe(system.glitchClusters)) | mic f=\(mic.measuredFrequency) clean=\(mic.cleanFraction) silent=\(mic.silentSeconds)s glitches=\(Analysis.describe(mic.glitchClusters))")

        // Right pitch: a 44.1kHz stream labelled 48kHz plays 8.8% sharp.
        #expect(abs(system.measuredFrequency / Scenario.systemTone - 1) < 0.002, Comment(rawValue: "system tone came out at \(system.measuredFrequency) Hz"))
        #expect(abs(mic.measuredFrequency / Scenario.micTone - 1) < 0.002, Comment(rawValue: "mic tone came out at \(mic.measuredFrequency) Hz"))

        // No clicks: the only discontinuities allowed are where a source
        // really had no audio — the system tap starting late, its rebuild
        // after the output switch, and the mic's device switch.
        #expect(system.glitchClusters.count <= 3, Comment(rawValue: "system stream glitches (\(system.glitchClusters.count)) at \(Analysis.describe(system.glitchClusters))"))
        #expect(mic.glitchClusters.count <= 2, Comment(rawValue: "mic stream glitches (\(mic.glitchClusters.count)) at \(Analysis.describe(mic.glitchClusters))"))

        // Everything audible is clean tone (the few windows straddling the
        // allowed boundaries above are the only exceptions).
        #expect(system.cleanFraction > 0.995, Comment(rawValue: "system clean fraction \(system.cleanFraction)"))
        #expect(mic.cleanFraction > 0.995, Comment(rawValue: "mic clean fraction \(mic.cleanFraction)"))

        // And no audio went missing: silence only where a source really had
        // none — system: 1.8s before the tap started + 1.5s rebuild; mic: the
        // 0.7s device switch (plus a little slack for alignment).
        #expect(system.silentSeconds < 1.8 + 1.5 + 0.2, Comment(rawValue: "system silent for \(system.silentSeconds)s"))
        #expect(mic.silentSeconds < 0.7 + 0.2, Comment(rawValue: "mic silent for \(mic.silentSeconds)s"))
    }

    @Test func micOnlyWhenTheSystemTapNeverStarts() throws {
        var scenario = Scenario.realisticMeeting
        scenario.systemTapFails = true
        var simulation = Simulation(scenario: scenario)
        let result = try simulation.run()
        let mic = Analysis(samples: result.mic, toneFrequency: Scenario.micTone)
        print("SIM mic-only clean=\(mic.cleanFraction) glitches=\(Analysis.describe(mic.glitchClusters))")
        #expect(mic.glitchClusters.count <= 2, Comment(rawValue: "mic stream glitches (\(mic.glitchClusters.count)) at \(Analysis.describe(mic.glitchClusters))"))
        #expect(abs(mic.measuredFrequency / Scenario.micTone - 1) < 0.002)
    }

    /// Both sources carry a short burst at the same real moments (someone
    /// clapping, heard by the mic and in the call). In the recording they
    /// must line up, or remote speech and the mic's pickup of it smear into
    /// an echo.
    @Test(arguments: [44100.0, 48000.0])
    func micAndSystemStayAligned(outputDeviceRate: Double) throws {
        var scenario = Scenario.realisticMeeting
        scenario.system.segments[0].rate = outputDeviceRate
        scenario.signal = .bursts(every: 2.0)
        var simulation = Simulation(scenario: scenario)
        let result = try simulation.run()

        let micBursts = Analysis.burstOnsets(in: result.mic)
        let systemBursts = Analysis.burstOnsets(in: result.system)
        var offsets: [Double] = []
        for s in systemBursts {
            guard let m = micBursts.min(by: { abs($0 - s) < abs($1 - s) }), abs(m - s) < 0.5 else { continue }
            offsets.append(s - m)
        }
        #expect(offsets.count >= 20, Comment(rawValue: "only \(offsets.count) burst pairs found"))
        let worst = offsets.map(abs).max() ?? .infinity
        let offsetsMs: [Int] = offsets.map { Int($0 * 1000) }
        #expect(worst < 0.03, Comment(rawValue: "mic/system misaligned by up to \(Int(worst * 1000)) ms: \(offsetsMs)"))
    }
}

// MARK: - Scenario description

private struct Scenario {
    static let systemTone = 440.0
    static let micTone = 1000.0

    struct Segment {
        var start: Double      // real time the device starts delivering
        var end: Double        // real time it stops (rebuild / device switch)
        var rate: Double       // nominal rate the device actually runs at
        var drift: Double      // true rate = rate × (1 + drift)
    }

    struct Device {
        var segments: [Segment]
        var framesPerBuffer: Int
        var channels: Int
        var interleaved: Bool
        var jitter: Double                       // ± seconds on each callback
        var hiccups: [Hiccup] // thread stalls, data intact
    }

    struct Hiccup { var at: Double; var delay: Double }

    enum Signal { case tones, bursts(every: Double) }

    var duration: Double
    var mic: Device
    var system: Device
    var systemTapFails = false
    var pumpLateAt: [Hiccup]
    var signal: Signal = .tones

    static let realisticMeeting = Scenario(
        duration: 60,
        mic: Device(
            segments: [
                Segment(start: 0.0, end: 36.0, rate: 48000, drift: 35e-6),
                // Mic device switch (e.g. headset plugged in): ~0.7s with no input.
                Segment(start: 36.7, end: 60, rate: 48000, drift: -15e-6),
            ],
            framesPerBuffer: 4800, channels: 1, interleaved: false,
            jitter: 0.003,
            hiccups: [Hiccup(at: 21.3, delay: 0.06)]
        ),
        system: Device(
            segments: [
                // Process Tap creation can take seconds; recording starts with mic only.
                Segment(start: 1.8, end: 28.0, rate: 44100, drift: -20e-6),
                // Output device switched → tap rebuilt (~1.5s gap), now at 48kHz.
                Segment(start: 29.5, end: 60, rate: 48000, drift: 10e-6),
            ],
            framesPerBuffer: 512, channels: 2, interleaved: true,
            jitter: 0.001,
            hiccups: [Hiccup(at: 12.4, delay: 0.08), Hiccup(at: 44.0, delay: 0.045)]
        ),
        pumpLateAt: [Hiccup(at: 17.0, delay: 0.2), Hiccup(at: 50.2, delay: 0.12)]
    )
}

// MARK: - Simulation

private struct Simulation {
    let scenario: Scenario
    var rng = SplitMix64(seed: 0x4B59_2026_1009)

    init(scenario: Scenario) {
        self.scenario = scenario
    }

    enum Kind { case mic(AVAudioPCMBuffer, start: Double), system(AVAudioPCMBuffer, start: Double), pump }
    struct Event { var time: Double; var order: Int; var kind: Kind }

    mutating func run() throws -> (mic: [Float], system: [Float]) {
        let pipeline = MixPipeline(hasSystemSource: !scenario.systemTapFails)
        var events: [Event] = []
        var order = 0
        func add(_ time: Double, _ kind: Kind) {
            events.append(Event(time: time, order: order, kind: kind))
            order += 1
        }

        for buffer in try deviceBuffers(scenario.mic, isSystem: false) { add(buffer.time, .mic(buffer.buffer, start: buffer.start)) }
        if !scenario.systemTapFails {
            for buffer in try deviceBuffers(scenario.system, isSystem: true) { add(buffer.time, .system(buffer.buffer, start: buffer.start)) }
        }

        // The 50ms pump timer (fixed deadlines, occasionally late).
        var t = 0.05
        while t < scenario.duration + 1 {
            var fire = t + rng.uniform(-0.004, 0.004)
            if let late = scenario.pumpLateAt.first(where: { abs($0.at - t) < 0.025 }) { fire += late.delay }
            add(fire, .pump)
            t += 0.05
        }

        events.sort { ($0.time, $0.order) < ($1.time, $1.order) }
        var mic: [Float] = []
        var system: [Float] = []
        for event in events {
            switch event.kind {
            case .mic(let buffer, let start): pipeline.ingestMic(buffer, startTime: start, arrival: event.time)
            case .system(let buffer, let start): pipeline.ingestSystem(buffer, startTime: start, arrival: event.time)
            case .pump:
                let chunk = pipeline.pump(now: event.time)
                mic += chunk.mic
                system += chunk.system
            }
        }
        let tail = pipeline.pump(now: scenario.duration + 2, flush: true)
        mic += tail.mic
        system += tail.system
        return (mic, system)
    }

    private func value(at time: Double, isSystem: Bool) -> Float {
        switch scenario.signal {
        case .tones:
            let f = isSystem ? Scenario.systemTone : Scenario.micTone
            return Float((isSystem ? 0.5 : 0.3) * sin(2 * .pi * f * time))
        case .bursts(let every):
            let phase = time.truncatingRemainder(dividingBy: every)
            guard phase < 0.004 else { return 0 }
            return Float(0.6 * sin(2 * .pi * 3000 * phase) * sin(.pi * phase / 0.004))
        }
    }

    /// Buffers exactly as the device would deliver them, labelled with the
    /// format production code assigns: `SystemAudioTap.captureFormat` for the
    /// tap (which only knows the tap's reported 48kHz ASBD and the aggregate
    /// device's nominal rate), the input node's format for the mic.
    private mutating func deviceBuffers(_ device: Scenario.Device, isSystem: Bool) throws -> [(time: Double, start: Double, buffer: AVAudioPCMBuffer)] {
        var result: [(Double, Double, AVAudioPCMBuffer)] = []
        for segment in device.segments {
            let format: AVAudioFormat
            if isSystem {
                let tapASBD = AudioStreamBasicDescription(
                    mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                    mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
                )
                format = try #require(SystemAudioTap.captureFormat(tapFormat: tapASBD, aggregateNominalSampleRate: segment.rate))
            } else {
                format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: segment.rate, channels: 1, interleaved: false))
            }
            let trueRate = segment.rate * (1 + segment.drift)
            let n = device.framesPerBuffer
            var frame = 0
            while true {
                let bufferStart = segment.start + Double(frame) / trueRate
                let bufferEnd = segment.start + Double(frame + n) / trueRate
                guard bufferEnd <= min(segment.end, scenario.duration) else { break }
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)))
                buffer.frameLength = AVAudioFrameCount(n)
                let data = try #require(buffer.floatChannelData)
                for i in 0..<n {
                    let v = value(at: bufferStart + Double(i) / trueRate, isSystem: isSystem)
                    if device.interleaved {
                        for c in 0..<device.channels { data[0][i * device.channels + c] = v }
                    } else {
                        for c in 0..<device.channels { data[c][i] = v }
                    }
                }
                var arrival = bufferEnd + 0.002 + rng.uniform(0, device.jitter)
                for hiccup in device.hiccups where arrival >= hiccup.at && arrival < hiccup.at + hiccup.delay {
                    arrival = hiccup.at + hiccup.delay + rng.uniform(0, 0.001) // backlog delivered in a burst
                }
                // Hardware timestamp of the first sample, with a little noise.
                result.append((arrival, bufferStart + rng.uniform(-0.0003, 0.0003), buffer))
                frame += n
            }
        }
        // Callbacks of one device are serial: a burst can't overtake.
        var last = 0.0
        for index in result.indices {
            last = max(last, result[index].0)
            result[index].0 = last
        }
        return result.map { (time: $0.0, start: $0.1, buffer: $0.2) }
    }
}

// MARK: - Analysis

private struct Analysis {
    static let sampleRate = 48000.0
    let measuredFrequency: Double
    /// Start times (s) of runs of damaged audio, merged within 50ms.
    let glitchClusters: [Double]
    /// Fraction of the audible 10ms windows that are clean tone.
    let cleanFraction: Double
    /// Total time the stream was silent.
    let silentSeconds: Double

    init(samples: [Float], toneFrequency: Double) {
        let x = samples.map(Double.init)
        measuredFrequency = Self.frequency(of: x, near: toneFrequency)

        // Fit A·sin + B·cos (+DC) at the measured frequency in each 10ms
        // window; a clean tone leaves almost nothing behind.
        let window = 480
        let hop = 240
        var clean = 0
        var total = 0
        var silent = 0
        // The very end is where one source's last buffer simply ends a few ms
        // before the other's — the recording stops there, not a glitch.
        let analysedCount = max(0, x.count - Int(0.3 * Self.sampleRate))
        var bad: [Double] = []
        var previous: Bool? = nil // was the previous window tone (true) or silence (false)?
        var start = 0
        let fitter = ToneFitter(frequency: measuredFrequency, window: window)
        x.withUnsafeBufferPointer { all in
            while start + window <= analysedCount {
                let seg = UnsafeBufferPointer(rebasing: all[start..<start + window])
                var energy = 0.0
                for v in seg { energy += v * v }
                energy /= Double(window)
                let time = Double(start) / Self.sampleRate
                if energy < 1e-7 {
                    silent += 1
                    // Silence: fine (the source had no audio), but entering
                    // or leaving it is a discontinuity.
                    if previous == true { bad.append(time) }
                    previous = false
                } else {
                    total += 1
                    if fitter.residualRatio(seg) < 1e-4 { // −40 dB
                        clean += 1
                        if previous == false { bad.append(time) }
                    } else {
                        bad.append(time)
                    }
                    previous = true
                }
                start += hop
            }
        }
        cleanFraction = total == 0 ? 0 : Double(clean) / Double(total)
        silentSeconds = Double(silent) * Double(hop) / Self.sampleRate
        // Merge consecutive bad windows into one cluster (by start time).
        var merged: [Double] = []
        var lastBad = -1.0
        for t in bad {
            if t - lastBad > 0.05 { merged.append(t) }
            lastBad = t
        }
        glitchClusters = merged
    }

    static func describe(_ times: [Double]) -> String {
        times.prefix(15).map { String(format: "%.2fs", $0) }.joined(separator: ", ") + (times.count > 15 ? ", …" : "")
    }

    /// Frequency from zero crossings over the non-silent part.
    static func frequency(of x: [Double], near expected: Double) -> Double {
        var crossings: [Double] = []
        for i in 1..<x.count where x[i - 1] < 0 && x[i] >= 0 && abs(x[i] - x[i - 1]) < 0.5 {
            let frac = -x[i - 1] / (x[i] - x[i - 1])
            crossings.append(Double(i - 1) + frac)
        }
        guard crossings.count > 2 else { return 0 }
        // Median period of consecutive crossings, ignoring gaps.
        var periods: [Double] = []
        for i in 1..<crossings.count {
            let p = crossings[i] - crossings[i - 1]
            if p > 0.5 * sampleRate / expected && p < 2 * sampleRate / expected { periods.append(p) }
        }
        periods.sort()
        guard !periods.isEmpty else { return 0 }
        let mean = periods[periods.count / 10..<periods.count * 9 / 10].reduce(0, +) / Double(periods.count * 8 / 10)
        return sampleRate / mean
    }

    /// Onset times (s) of short bursts: first sample above a threshold after
    /// at least 0.5s of quiet.
    static func burstOnsets(in samples: [Float]) -> [Double] {
        var onsets: [Double] = []
        var lastLoud = -Double.infinity
        for (i, v) in samples.enumerated() where abs(v) > 0.1 {
            let t = Double(i) / sampleRate
            if t - lastLoud > 0.5 { onsets.append(t) }
            lastLoud = t
        }
        return onsets
    }
}

/// Least-squares fit of A·sin + B·cos + C at one frequency over a fixed
/// window; the basis and its normal-equation inverse are precomputed once.
private struct ToneFitter {
    let sinTable: [Double]
    let cosTable: [Double]
    let inverse: [Double] // 3×3, row-major

    init(frequency: Double, window: Int) {
        let w = 2 * Double.pi * frequency / Analysis.sampleRate
        sinTable = (0..<window).map { sin(w * Double($0)) }
        cosTable = (0..<window).map { cos(w * Double($0)) }
        var m = [Double](repeating: 0, count: 9)
        for i in 0..<window {
            let b = [sinTable[i], cosTable[i], 1.0]
            for r in 0..<3 { for c in 0..<3 { m[r * 3 + c] += b[r] * b[c] } }
        }
        inverse = Self.invert3(m)
    }

    func residualRatio(_ seg: UnsafeBufferPointer<Double>) -> Double {
        var p0 = 0.0, p1 = 0.0, p2 = 0.0, total = 0.0
        for i in 0..<seg.count {
            let y = seg[i]
            p0 += sinTable[i] * y
            p1 += cosTable[i] * y
            p2 += y
            total += y * y
        }
        let a = inverse[0] * p0 + inverse[1] * p1 + inverse[2] * p2
        let b = inverse[3] * p0 + inverse[4] * p1 + inverse[5] * p2
        let c = inverse[6] * p0 + inverse[7] * p1 + inverse[8] * p2
        // Residual energy = Σy² − coefᵀ·(Bᵀy) for a least-squares fit.
        let explained = a * p0 + b * p1 + c * p2
        return total > 0 ? max(0, total - explained) / total : 0
    }

    private static func invert3(_ m: [Double]) -> [Double] {
        let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return [
            (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
            (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
            (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det,
        ]
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * Double(next() >> 11) / Double(1 << 53)
    }
}
