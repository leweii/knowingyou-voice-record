import Testing
@testable import KnowingYou

struct LevelMeterViewTests {
    @Test func silenceLightsNoSegments() {
        #expect(LevelMeterView.litSegmentCount(for: 0) == 0)
    }

    @Test func fullScaleLightsAllFiveSegments() {
        #expect(LevelMeterView.litSegmentCount(for: 1) == 5)
    }

    @Test func eachThresholdLightsExactlyThatManySegments() {
        #expect(LevelMeterView.litSegmentCount(for: 0.1) == 1)
        #expect(LevelMeterView.litSegmentCount(for: 0.3) == 2)
        #expect(LevelMeterView.litSegmentCount(for: 0.5) == 3)
        #expect(LevelMeterView.litSegmentCount(for: 0.7) == 4)
        #expect(LevelMeterView.litSegmentCount(for: 0.85) == 5)
    }

    @Test func justBelowAThresholdDoesNotLightThatSegment() {
        #expect(LevelMeterView.litSegmentCount(for: 0.09) == 0)
        #expect(LevelMeterView.litSegmentCount(for: 0.29) == 1)
        #expect(LevelMeterView.litSegmentCount(for: 0.84) == 4)
    }

    @Test func segmentCountIsMonotonicallyNondecreasing() {
        var previous = 0
        var level: Float = 0
        while level <= 1 {
            let count = LevelMeterView.litSegmentCount(for: level)
            #expect(count >= previous)
            previous = count
            level += 0.05
        }
    }
}
