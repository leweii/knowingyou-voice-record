import AppKit
import Testing
@testable import KnowingYou

struct FloatingWidgetPlacementTests {
    private let size = CGSize(width: 264, height: 48)
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func placesPillInsideTopRightOfWindow() {
        let window = NSRect(x: 100, y: 200, width: 800, height: 500)
        let origin = FloatingWidgetPanel.pillOrigin(windowFrame: window, visibleFrame: visible, size: size)
        #expect(origin == NSPoint(x: 900 - 264 - 16, y: 700 - 48 - 16))
    }

    @Test func clampsWindowThatExtendsPastTheScreen() {
        let window = NSRect(x: 1000, y: 500, width: 800, height: 600) // past right edge and under menu bar
        let origin = FloatingWidgetPanel.pillOrigin(windowFrame: window, visibleFrame: visible, size: size)
        #expect(origin == NSPoint(x: 1440 - 264 - 16, y: 875 - 48 - 16))
    }

    @Test func clampsWindowNarrowerThanThePill() {
        let window = NSRect(x: -50, y: 0, width: 150, height: 40) // off the left/bottom edge
        let origin = FloatingWidgetPanel.pillOrigin(windowFrame: window, visibleFrame: visible, size: size)
        #expect(origin == NSPoint(x: 16, y: 16))
    }
}
