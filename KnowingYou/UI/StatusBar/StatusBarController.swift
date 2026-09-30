import AppKit
import Observation

/// Owns the `NSStatusItem`: left-click toggles the borderless popover
/// (`PopoverPanel`), right-click (or ⌃-click) shows a plain `NSMenu` with
/// Preferences/Quit/Debug. The breathing dot (02-ui-spec.md §8) overlays the
/// template icon — red while actually recording, orange while a whitelisted
/// app is using the mic but nothing's recording yet (`.meetingActive`).
/// The orange state exists specifically so a user who denied the
/// notifications permission still has *some* visible sign a meeting was
/// detected, instead of the confirmation prompt only ever existing as a
/// system notification they'll never see (S20 edge case #14).
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
        FloatingPromptPanel.shared.anchorFrameProvider = { [weak self] in
            self?.statusItem.button?.window?.frame
        }
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
            _ = appState.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateDot()
                self?.trackRecordingState()
            }
        }
        updateDot()
    }

    private func updateDot() {
        switch appState.phase {
        case .recording:
            showDot(color: NSColor(KYColor.rec), breathes: true)
        case .meetingActive:
            showDot(color: NSColor(KYColor.warn), breathes: false)
        case .idle, .finalizing:
            hideDot()
        }
    }

    /// Red = recording (breathes, 1.6s like every other "live" dot in the
    /// app); amber = meeting detected, not recording (steady — it's a
    /// "look here" hint, not a live signal).
    private func showDot(color: NSColor, breathes: Bool) {
        guard let button = statusItem.button, let layer = button.layer else { return }
        let dot: CALayer
        if let dotLayer {
            dot = dotLayer
        } else {
            let size: CGFloat = 7
            dot = CALayer()
            dot.frame = CGRect(x: button.bounds.width - size - 1, y: 1, width: size, height: size)
            dot.cornerRadius = size / 2
            dot.shadowOffset = .zero
            dot.shadowRadius = 3
            layer.addSublayer(dot)
            dotLayer = dot
        }
        let resolved = color.usingColorSpace(.sRGB) ?? color
        dot.backgroundColor = resolved.cgColor
        dot.shadowColor = resolved.cgColor
        dot.removeAnimation(forKey: "breathing")
        dot.removeAnimation(forKey: "breathing-fade")
        dot.opacity = 1
        dot.shadowOpacity = 0.8
        guard breathes, !KYMotion.reduceMotion else { return }
        let breathe = CABasicAnimation(keyPath: "shadowOpacity")
        breathe.fromValue = 0.9
        breathe.toValue = 0.1
        breathe.duration = KYMotion.breatheDuration / 2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.55
        fade.duration = KYMotion.breatheDuration / 2
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(breathe, forKey: "breathing")
        dot.add(fade, forKey: "breathing-fade")
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
