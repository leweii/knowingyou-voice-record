import Foundation

/// Pure sample-array math for combining the mic and system-audio streams.
/// Buffer alignment/queuing lives in `RecordingSession`; this file only
/// operates on already-aligned, equal-length mono sample arrays.
enum Mixer {
    /// `(mic + system) / 2`, soft-limited so simultaneous full-scale input on
    /// both channels can't clip.
    static func monoMix(mic: [Float], system: [Float]) -> [Float] {
        precondition(mic.count == system.count, "Mixer.monoMix requires equal-length inputs")
        return zip(mic, system).map { softLimit(($0 + $1) * 0.5) }
    }

    /// Interleaved stereo: left = mic, right = system. No mixing, no limiting
    /// (each channel is just the original signal).
    static func dualTrack(mic: [Float], system: [Float]) -> [Float] {
        precondition(mic.count == system.count, "Mixer.dualTrack requires equal-length inputs")
        var interleaved = [Float]()
        interleaved.reserveCapacity(mic.count * 2)
        for index in mic.indices {
            interleaved.append(mic[index])
            interleaved.append(system[index])
        }
        return interleaved
    }

    /// Soft limiter (tanh-based) — keeps values in -1...1 without the hard
    /// clipping a simple `min/max` clamp would produce.
    static func softLimit(_ sample: Float) -> Float {
        tanh(sample)
    }

    /// How many frames to mix in one pump pass, given how much each source
    /// has queued. Normally only the frames *both* sources have delivered
    /// (`min`), so ordinary buffer-arrival jitter just waits for the late
    /// source instead of filling its gap with silence — doing the latter
    /// every 50ms tick is what made recordings choppy (2026-10-05). Only when
    /// one source has fallen more than `maxLag` frames behind (it stalled:
    /// device switch, tap died) is it zero-padded, so the other keeps
    /// flowing. `systemAvailable == nil` means there is no system source.
    /// `flush` (on stop) takes everything that's left.
    static func framesToMix(micAvailable: Int, systemAvailable: Int?, maxLag: Int, flush: Bool = false) -> Int {
        guard let systemAvailable else { return micAvailable }
        let longest = max(micAvailable, systemAvailable)
        if flush { return longest }
        return max(min(micAvailable, systemAvailable), longest - maxLag)
    }

    /// Pads with trailing zeros so both streams cover the same number of
    /// frames — used to cover input gaps during device reconfiguration and
    /// keep the recording's timeline continuous.
    static func zeroPadded(_ samples: [Float], to count: Int) -> [Float] {
        guard samples.count < count else { return samples }
        return samples + [Float](repeating: 0, count: count - samples.count)
    }
}
