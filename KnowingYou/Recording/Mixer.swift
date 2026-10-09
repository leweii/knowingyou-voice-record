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

    /// Pads with trailing zeros so both streams cover the same number of
    /// frames — used to cover input gaps during device reconfiguration and
    /// keep the recording's timeline continuous.
    static func zeroPadded(_ samples: [Float], to count: Int) -> [Float] {
        guard samples.count < count else { return samples }
        return samples + [Float](repeating: 0, count: count - samples.count)
    }
}
