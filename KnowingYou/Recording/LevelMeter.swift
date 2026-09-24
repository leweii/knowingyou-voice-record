import AVFoundation

/// Pure level-metering math. Actual metering happens on the `onBuffer`
/// consumer side (S09/S15); this file only supplies the functions.
enum LevelMeter {
    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sumOfSquares: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sumOfSquares += sample * sample
            }
        }
        let count = Float(frameLength * channelCount)
        return sqrt(sumOfSquares / count)
    }

    /// Same computation for a plain mono sample array — used by S09's
    /// `RecordingSession`, which already has extracted Float arrays rather
    /// than an `AVAudioPCMBuffer` at the point it wants a level reading.
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    /// dBFS relative to a full-scale sine (amplitude 1.0). Silence maps to
    /// `-.infinity`, not a crash or NaN.
    static func dbfs(_ rms: Float) -> Float {
        guard rms > 0 else { return -.infinity }
        return 20 * log10(rms)
    }

    /// Maps raw linear RMS onto the 0...1 scale `LevelMeterView`'s thresholds
    /// (0.1/0.3/0.5/0.7/0.85) expect. Feeding linear RMS straight into those
    /// thresholds was the bug behind "the meter never moves while talking"
    /// (found 2026-09-24 by Jakob on a real Mac): normal conversational
    /// speech sits around -30…-15 dBFS, which is only ~0.03–0.18 in *linear*
    /// amplitude — well under even the first 0.1 threshold — so the meter
    /// only ever lit up for near-clipping volume. This rescales using a dB
    /// floor instead, since loudness (and the segments' visual thresholds)
    /// is a perceptual/logarithmic quantity, not a linear one.
    static func normalizedLevel(fromRMS rms: Float, floorDB: Float = -50) -> Float {
        let db = dbfs(rms)
        guard db.isFinite else { return 0 }
        return min(max((db - floorDB) / -floorDB, 0), 1)
    }
}

/// Fast attack / slow decay smoother for UI level meters (pill/notes-window
/// level bars). Output is clamped to 0...1.
struct LevelSmoother {
    var attackCoefficient: Float = 0.6
    var decayCoefficient: Float = 0.15
    private(set) var value: Float = 0

    @discardableResult
    mutating func update(with newValue: Float) -> Float {
        let target = min(max(newValue, 0), 1)
        let coefficient = target > value ? attackCoefficient : decayCoefficient
        value += (target - value) * coefficient
        return value
    }

    mutating func reset() {
        value = 0
    }
}
