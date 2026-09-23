import AppKit
import SwiftUI

/// Single-instance 480×360 first-run window. Uses a plain `NSWindow`, not a
/// panel: an `LSUIElement` app's windows won't come forward without an
/// explicit `activate(ignoringOtherApps:)`, which `bringToFront` does.
@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            bringToFront(window)
            return
        }

        let hosting = NSHostingController(rootView: OnboardingView(onFinish: finish))
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "首次启动"
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 480, height: 360))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        bringToFront(newWindow)
        window = newWindow
    }

    private static func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func finish() {
        Preferences.shared.hasCompletedOnboarding = true
        window?.close()
    }
}
