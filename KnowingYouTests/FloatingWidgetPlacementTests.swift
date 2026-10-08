import AppKit
import Testing
@testable import KnowingYou

struct FloatingWidgetPlacementTests {
    @Test func defaultOriginIsTopRightInsetByMargin() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let origin = FloatingWidgetPanel.defaultOrigin(visibleFrame: visible, size: CGSize(width: 264, height: 48), margin: 20)
        #expect(origin == NSPoint(x: 1440 - 264 - 20, y: 875 - 48 - 20))
    }

    @Test func defaultOriginRespectsASecondaryScreenOffset() {
        let visible = NSRect(x: 1440, y: -200, width: 1920, height: 1055)
        let origin = FloatingWidgetPanel.defaultOrigin(visibleFrame: visible, size: CGSize(width: 264, height: 48), margin: 20)
        #expect(origin == NSPoint(x: 1440 + 1920 - 264 - 20, y: -200 + 1055 - 48 - 20))
    }
}

struct WaveformHistoryTests {
    @Test func samplesAtAFixedRateRegardlessOfUpdateTiming() {
        let history = WaveformHistory()
        #expect(history.advance(to: 10.0, level: 0.5, capacity: 4, period: 0.05) == 0)
        // Half a period later: no new bar yet, halfway scrolled.
        let phase = history.advance(to: 10.025, level: 0.5, capacity: 4, period: 0.05)
        #expect(history.values.isEmpty)
        #expect(abs(phase - 0.5) < 0.001)
        // 3 periods later (one slow frame): exactly 3 bars, not 1.
        _ = history.advance(to: 10.15, level: 0.8, capacity: 4, period: 0.05)
        #expect(history.values == [0.8, 0.8, 0.8])
    }

    @Test func keepsOnlyCapacityBarsAndPadsOnTheLeft() {
        let history = WaveformHistory()
        _ = history.advance(to: 0, level: 0, capacity: 3, period: 0.05)
        _ = history.advance(to: 1, level: 0.2, capacity: 3, period: 0.05)
        #expect(history.values.count == 3)
        history.reset()
        _ = history.advance(to: 0, level: 0, capacity: 3, period: 0.05)
        _ = history.advance(to: 0.05, level: 0.4, capacity: 3, period: 0.05)
        #expect(history.padded(to: 3) == [0, 0, 0.4])
    }

    @Test func restartingTheClockDoesNotBackfillAPause() {
        let history = WaveformHistory()
        _ = history.advance(to: 0, level: 0.3, capacity: 10, period: 0.05)
        _ = history.advance(to: 0.1, level: 0.3, capacity: 10, period: 0.05)
        history.restartClock()
        _ = history.advance(to: 60, level: 0.9, capacity: 10, period: 0.05)
        #expect(history.values == [0.3, 0.3])
    }
}
