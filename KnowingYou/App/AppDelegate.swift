import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Preferences.shared.showDockIcon ? .regular : .accessory)
        configureStatusItem()
        AppLog.app.info("KnowingYou launched")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = KYBrand.statusBarTemplateImage
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "偏好设置…", action: nil, keyEquivalent: ","))
        menu.addItem(.separator())
        #if DEBUG
        menu.addItem(debugMenuItem())
        menu.addItem(.separator())
        #endif
        menu.addItem(withTitle: "退出知鱼录音", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu

        statusItem = item
    }

    #if DEBUG
    private func debugMenuItem() -> NSMenuItem {
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(withTitle: "控件画廊", action: #selector(showDesignSystemGallery), keyEquivalent: "")
        for menuItem in submenu.items {
            menuItem.target = self
        }
        debugItem.submenu = submenu
        return debugItem
    }

    @objc private func showDesignSystemGallery() {
        DesignSystemGalleryWindow.show()
    }
    #endif

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
