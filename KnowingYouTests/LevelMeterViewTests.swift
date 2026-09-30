import CoreGraphics
import Testing
@testable import KnowingYou

struct LevelMeterViewTests {
    @Test func silenceMapsToMinHeight() {
        #expect(LevelMeterView.barHeight(for: 0, minHeight: 4, maxHeight: 16) == 4)
    }

    @Test func fullScaleMapsToMaxHeight() {
        #expect(LevelMeterView.barHeight(for: 1, minHeight: 4, maxHeight: 16) == 16)
    }

    @Test func midLevelMapsHalfwayBetweenMinAndMax() {
        let height = LevelMeterView.barHeight(for: 0.5, minHeight: 4, maxHeight: 16)
        #expect(abs(height - 10) < 0.001)
    }

    @Test func heightIsMonotonicallyNondecreasingWithLevel() {
        var previous: CGFloat = -1
        var level: Float = 0
        while level <= 1 {
            let height = LevelMeterView.barHeight(for: level, minHeight: 4, maxHeight: 16)
            #expect(height >= previous)
            previous = height
            level += 0.05
        }
    }

    @Test func clampsOutOfRangeLevelToMinMax() {
        #expect(LevelMeterView.barHeight(for: -5, minHeight: 4, maxHeight: 16) == 4)
        #expect(LevelMeterView.barHeight(for: 5, minHeight: 4, maxHeight: 16) == 16)
    }

    @Test func respectsCustomMinAndMaxHeight() {
        #expect(LevelMeterView.barHeight(for: 0, minHeight: 3, maxHeight: 12) == 3)
        #expect(LevelMeterView.barHeight(for: 1, minHeight: 3, maxHeight: 12) == 12)
    }

    /// S22: bars are colored by loudness — accent (0), amber (1) from 0.6,
    /// red (2) from 0.85 — so near-clipping peaks stand out.
    @Test func colorBandThresholds() {
        #expect(LevelMeterView.band(for: 0) == 0)
        #expect(LevelMeterView.band(for: 0.59) == 0)
        #expect(LevelMeterView.band(for: 0.6) == 1)
        #expect(LevelMeterView.band(for: 0.84) == 1)
        #expect(LevelMeterView.band(for: 0.85) == 2)
        #expect(LevelMeterView.band(for: 1.5) == 2)
    }
}
