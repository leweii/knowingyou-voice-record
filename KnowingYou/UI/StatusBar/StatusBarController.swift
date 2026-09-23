import AppKit
import Observation

/// Owns the `NSStatusItem`: left-click toggles the borderless popover
/// (`PopoverPanel`), right-click (or ⌃-click) shows a plain `NSMenu` with
/// Preferences/Quit/Debug. The breathing red dot (02-ui-spec.md §8) overlays
/// the template icon while `appState.isRecording`.
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let contextMenu: NSMenu
    private lazy var popoverPanel = PopoverPanel(
        appState: appState,
        statusItem: statusItem,
        onOpenSaveDirectory: { [weak self] in self?.openSaveDirectory() },
        onOpenSettings: { [weak self] in SettingsWindowController.show() }
    )
    private var dotLayer: CALayer?
    private var clickTarget: ClickTarget?

    init(appState: AppState, contextMenu: NSMenu) {
        self.appState = appState
        self.contextMenu = contextMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()
        trackRecordingState()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = KYBrand.statusBarTemplateImage
        button.wantsLayer = true
        let target = ClickTarget { [weak self] in self?.handleClick() }
        clickTarget = target
        button.target = target
        button.action = #selector(ClickTarget.fire)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            popoverPanel.toggle()
        }
    }

    private func showContextMenu() {
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func openSaveDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: RecordingStore.shared.rootDirectory.path)
    }

    /// `AppState` is `@Observable`; this is the standard way to observe one
    /// from outside SwiftUI (the popover's own SwiftUI content re-renders on
    /// its own — this loop only drives the AppKit-side breathing dot).
    private func trackRecordingState() {
        withObservationTracking {
            _ = appState.isRecording
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateDot()
                self?.trackRecordingState()
            }
        }
        updateDot()
    }

    private func updateDot() {
        if appState.isRecording {
            showDot()
        } else {
            hideDot()
        }
    }

    private func showDot() {
        guard dotLayer == nil, let button = statusItem.button, let layer = button.layer else { return }
        let size: CGFloat = 6
        let dot = CALayer()
        dot.frame = CGRect(x: button.bounds.width - size - 2, y: 2, width: size, height: size)
        dot.backgroundColor = NSColor.systemRed.cgColor
        dot.cornerRadius = size / 2
        layer.addSublayer(dot)

        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1.0
        breathe.toValue = 0.35
        breathe.duration = 1.0
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        dot.add(breathe, forKey: "breathing")

        dotLayer = dot
    }

    private func hideDot() {
        dotLayer?.removeFromSuperlayer()
        dotLayer = nil
    }
}

/// `NSStatusBarButton.target` must be an `NSObject`; `StatusBarController`
/// itself deliberately isn't one, so this tiny shim adapts a Swift closure
/// to the `@objc` selector-based target/action pattern.
private final class ClickTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}
