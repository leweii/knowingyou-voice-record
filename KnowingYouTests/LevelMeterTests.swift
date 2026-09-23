import AVFoundation
import Testing
@testable import KnowingYou

struct LevelMeterTests {
    private func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = buffer.floatChannelData![0]
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }

    private func sineWave(amplitude: Float, frequency: Float = 440, sampleRate: Float = 48000, count: Int = 4800) -> [Float] {
        (0..<count).map { i in amplitude * sin(2 * .pi * frequency * Float(i) / sampleRate) }
    }

    @Test func rmsOfSilenceIsZero() {
        let buffer = makeBuffer(samples: [Float](repeating: 0, count: 1024))
        #expect(LevelMeter.rms(buffer) == 0)
    }

    @Test func rmsOfFullScaleSineMatchesTheory() {
        // RMS of a sine with amplitude A is A/sqrt(2); for A=1 that's ~0.7071.
        let buffer = makeBuffer(samples: sineWave(amplitude: 1.0))
        let rms = LevelMeter.rms(buffer)
        #expect(abs(rms - 0.7071) < 0.001)
    }

    @Test func rmsScalesLinearlyWithAmplitude() {
        let full = LevelMeter.rms(makeBuffer(samples: sineWave(amplitude: 1.0)))
        let half = LevelMeter.rms(makeBuffer(samples: sineWave(amplitude: 0.5)))
        #expect(abs(half - full / 2) < 0.001)
    }

    @Test func dbfsOfSilenceIsNegativeInfinity() {
        #expect(LevelMeter.dbfs(0) == -.infinity)
    }

    @Test func dbfsOfFullScaleSineIsNearZero() {
        // A full-scale sine's RMS is -3.01 dBFS, not 0 - only its *peak* hits
        // 0 dBFS. "≈0" here means "near the top of the scale", not exactly 0.
        let rms = LevelMeter.rms(makeBuffer(samples: sineWave(amplitude: 1.0)))
        let dbfs = LevelMeter.dbfs(rms)
        #expect(abs(dbfs - (-3.01)) < 0.1)
    }

    @Test func dbfsDecreasesAsAmplitudeHalves() {
        let full = LevelMeter.dbfs(LevelMeter.rms(makeBuffer(samples: sineWave(amplitude: 1.0))))
        let half = LevelMeter.dbfs(LevelMeter.rms(makeBuffer(samples: sineWave(amplitude: 0.5))))
        // Halving amplitude drops the level by 6.02 dB, so full is 6.02 dB
        // *above* half (both values are negative, e.g. -3.01 vs -9.03).
        #expect(abs((full - half) - 6.02) < 0.1)
    }

    @Test func smootherConvergesMonotonicallyUpward() {
        var smoother = LevelSmoother()
        var previous: Float = 0
        for _ in 0..<50 {
            let value = smoother.update(with: 1.0)
            #expect(value >= previous)
            previous = value
        }
        #expect(previous > 0.9)
    }

    @Test func smootherDecaysMonotonicallyDownward() {
        var smoother = LevelSmoother()
        for _ in 0..<50 { smoother.update(with: 1.0) }
        var previous: Float = smoother.value
        for _ in 0..<50 {
            let value = smoother.update(with: 0.0)
            #expect(value <= previous)
            previous = value
        }
        #expect(previous < 0.1)
    }

    @Test func smootherAttackIsFasterThanDecay() {
        var attackSmoother = LevelSmoother()
        let afterOneAttackStep = attackSmoother.update(with: 1.0)

        var decaySmoother = LevelSmoother()
        for _ in 0..<50 { decaySmoother.update(with: 1.0) }
        let afterOneDecayStep = decaySmoother.update(with: 0.0)
        let decayDrop = 1.0 - afterOneDecayStep

        #expect(afterOneAttackStep > decayDrop)
    }

    @Test func smootherClampsOutOfRangeInput() {
        var smoother = LevelSmoother()
        #expect(smoother.update(with: 5.0) <= 1.0)
        smoother.reset()
        #expect(smoother.update(with: -5.0) >= 0.0)
    }
}
