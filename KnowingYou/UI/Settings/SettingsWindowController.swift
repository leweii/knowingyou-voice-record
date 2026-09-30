import AppKit
import SwiftUI

/// Single-instance preferences window (S22: transparent full-size title bar
/// so the sidebar runs to the top edge, traffic lights floating over it), opened from the status-bar
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
        // Don't let the hosting controller grow the window by the title bar's
        // safe-area inset — the content is laid out full-size under it.
        hosting.sizingOptions = []
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = String(localized: "偏好设置")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.setContentSize(SettingsRootView.size)
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
