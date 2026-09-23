import Testing
@testable import KnowingYou

struct MixerTests {
    @Test func monoMixAveragesTwoSignals() {
        let mic: [Float] = [0.02, 0.04, -0.02]
        let system: [Float] = [0.02, 0.0, 0.02]
        let mixed = Mixer.monoMix(mic: mic, system: system)
        // At these small magnitudes tanh(x) ≈ x (error is O(x^3)), so plain
        // averaging is a valid approximation to check against.
        #expect(abs(mixed[0] - 0.02) < 0.0001)
        #expect(abs(mixed[1] - 0.02) < 0.0001)
        #expect(abs(mixed[2] - 0.0) < 0.0001)
    }

    @Test func monoMixSilencePlusSilenceIsSilence() {
        let mixed = Mixer.monoMix(mic: [0, 0, 0], system: [0, 0, 0])
        #expect(mixed == [0, 0, 0])
    }

    @Test func monoMixSoftLimitsFullScaleInputs() {
        // Both channels at full scale: naive average would be 1.0 (borderline);
        // softLimit(tanh) should keep it strictly under 1.0 while staying close.
        let mixed = Mixer.monoMix(mic: [1.0], system: [1.0])
        #expect(mixed[0] < 1.0)
        #expect(mixed[0] > 0.7)
    }

    @Test func monoMixNeverExceedsUnityRegardlessOfInputMagnitude() {
        let mixed = Mixer.monoMix(mic: [10, -10, 100], system: [10, -10, -100])
        for sample in mixed {
            #expect(sample <= 1.0 && sample >= -1.0)
        }
    }

    @Test func dualTrackInterleavesWithoutMixing() {
        let mic: [Float] = [0.1, 0.2, 0.3]
        let system: [Float] = [0.9, 0.8, 0.7]
        let interleaved = Mixer.dualTrack(mic: mic, system: system)
        #expect(interleaved == [0.1, 0.9, 0.2, 0.8, 0.3, 0.7])
    }

    @Test func dualTrackLeftChannelIsOnlyMic() {
        let mic: [Float] = [0.5, 0.5]
        let system: [Float] = [0.0, 0.0]
        let interleaved = Mixer.dualTrack(mic: mic, system: system)
        let left = stride(from: 0, to: interleaved.count, by: 2).map { interleaved[$0] }
        #expect(left == [0.5, 0.5])
    }

    @Test func dualTrackRightChannelIsOnlySystem() {
        let mic: [Float] = [0.0, 0.0]
        let system: [Float] = [0.5, 0.5]
        let interleaved = Mixer.dualTrack(mic: mic, system: system)
        let right = stride(from: 1, to: interleaved.count, by: 2).map { interleaved[$0] }
        #expect(right == [0.5, 0.5])
    }

    @Test func zeroPaddedAppendsZerosToReachTargetCount() {
        let padded = Mixer.zeroPadded([1, 2, 3], to: 5)
        #expect(padded == [1, 2, 3, 0, 0])
    }

    @Test func zeroPaddedLeavesLongEnoughInputUnchanged() {
        let input: [Float] = [1, 2, 3, 4]
        #expect(Mixer.zeroPadded(input, to: 3) == input)
        #expect(Mixer.zeroPadded(input, to: 4) == input)
    }

    @Test func softLimitIsIdentityNearZero() {
        #expect(abs(Mixer.softLimit(0.1) - 0.0997) < 0.001)
    }

    @Test func softLimitApproachesButNeverReachesOne() {
        // tanh(1000) rounds to exactly 1.0f in Float32 - use a value large
        // enough to be near-saturated but small enough to stay distinguishable
        // from 1.0 at Float32 precision.
        #expect(Mixer.softLimit(5) < 1.0)
        #expect(Mixer.softLimit(5) > 0.999)
    }
}
