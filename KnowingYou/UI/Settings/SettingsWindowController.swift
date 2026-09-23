import AppKit
import SwiftUI

/// Single-instance 720×520 preferences window, opened from the status-bar
/// menu's "偏好设置…" item (⌘, in that menu).
@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window {
            bringToFront(window)
            return
        }

        let hosting = NSHostingController(rootView: SettingsRootView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = String(localized: "偏好设置")
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 720, height: 520))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        bringToFront(newWindow)
        window = newWindow
    }

    private static func bringToFront(_ window: NSWindow) {
        // The app has no Dock icon by default (LSUIElement); activate
        // explicitly so the window actually comes to the front and gets focus.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
