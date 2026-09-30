import AppKit
import SwiftUI

/// Single-instance first-run window. Uses a plain `NSWindow`, not a
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
        // Don't let the hosting controller grow the window by the title bar's
        // safe-area inset — the content is laid out full-size under it.
        hosting.sizingOptions = []
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = String(localized: "首次启动")
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.setContentSize(OnboardingView.size)
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
