import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Preferences.shared.showDockIcon ? .regular : .accessory)
        configureStatusItem()
        AppLog.app.info("KnowingYou launched")
        if !Preferences.shared.hasCompletedOnboarding {
            OnboardingWindow.show()
        }
        checkForRecoverableRecordings()
    }

    private func checkForRecoverableRecordings() {
        let candidates = RecordingStore.shared.recoveryCandidates
        guard !candidates.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "发现上次未完成的录音"
        alert.informativeText = "知鱼录音上次可能没有正常退出，是否把它恢复为可播放的录音文件？"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "稍后")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for url in candidates {
                Task {
                    do {
                        try await RecordingStore.shared.recover(url)
                    } catch {
                        AppLog.storage.error("recovery failed for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                    }
                }
            }
        case .alertSecondButtonReturn:
            for url in candidates {
                try? FileManager.default.removeItem(at: url)
            }
            RecordingStore.shared.refresh()
        default:
            break
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = KYBrand.statusBarTemplateImage
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "偏好设置…", action: #selector(openSettings), keyEquivalent: ",")
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
        submenu.addItem(withTitle: "重新引导", action: #selector(restartOnboarding), keyEquivalent: "")
        for menuItem in submenu.items {
            menuItem.target = self
        }
        debugItem.submenu = submenu
        return debugItem
    }

    @objc private func showDesignSystemGallery() {
        DesignSystemGalleryWindow.show()
    }

    @objc private func restartOnboarding() {
        Preferences.shared.hasCompletedOnboarding = false
        OnboardingWindow.show()
    }
    #endif

    @objc private func openSettings() {
        SettingsWindowController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
