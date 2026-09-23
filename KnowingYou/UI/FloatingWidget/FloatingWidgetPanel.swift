import AppKit
import SwiftUI

/// The pill-state floating widget (02-ui-spec.md §9 / plan §5.4): a
/// `.nonactivatingPanel` so it never steals focus from a meeting app,
/// draggable, position-persisting, visible above fullscreen apps.
/// `expand()`/the notes-window state (§10) is S16's job — `onExpand` is
/// wired up but currently a no-op, per this spec's scope.
@MainActor
final class FloatingWidgetPanel {
    static let shared = FloatingWidgetPanel()

    private var panel: NSPanel?
    private var hostingView: RoundedHostingView<PillView>?
    private var onStop: () -> Void = {}
    private var onExpand: () -> Void = {}
    private var moveObserver: NSObjectProtocol?

    /// Deliberately not constructed here: building an `NSPanel` at app-launch
    /// time (e.g. from a lazy `static let` touched during `applicationDidFinishLaunching`)
    /// crashed under the `xctest` host in this environment. Deferring window
    /// creation to the first real `show()` sidesteps that entirely and also
    /// means `make test` never creates a real window at all.
    private init() {}

    /// `onStop` should stop the current recording (`AppState.stopRecording()`);
    /// `onExpand` is unused in this spec (S16 fills it in).
    func configure(onStop: @escaping () -> Void, onExpand: @escaping () -> Void = {}) {
        self.onStop = onStop
        self.onExpand = onExpand
    }

    func show() {
        let panel = ensurePanel()
        positionPanel(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless() // never makeKey/activate — see S11's identical rule for the popover
    }

    func hide(animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1 // reset for the next `show()`
                _ = self // keep alive through the animation without extending its lifetime unnecessarily
            }
        }
    }

    func updateLevel(_ level: Float) {
        guard let hostingView else { return } // never shown yet — nothing to update
        rebuildContent(hostingView, level: level)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PillView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hostingView = RoundedHostingView(rootView: PillView(level: 0), cornerRadius: 12)
        hostingView.frame = NSRect(origin: .zero, size: PillView.size)
        panel.contentView = hostingView
        rebuildContent(hostingView, level: 0)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistOriginIfOnScreen() }
        }

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func rebuildContent(_ hostingView: RoundedHostingView<PillView>, level: Float) {
        hostingView.rootView = PillView(
            level: level,
            onExpand: { [weak self] in self?.onExpand() },
            onStop: { [weak self] in self?.onStop() }
        )
    }

    private func positionPanel(_ panel: NSPanel) {
        if let origin = Preferences.shared.floatingWidgetOrigin, isOnScreen(origin) {
            panel.setFrameOrigin(origin)
        } else {
            panel.setFrameOrigin(defaultOrigin())
        }
    }

    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        let x = frame.maxX - PillView.size.width - 16
        let y = frame.midY - PillView.size.height / 2
        return NSPoint(x: x, y: y)
    }

    private func isOnScreen(_ origin: CGPoint) -> Bool {
        let rect = NSRect(origin: origin, size: PillView.size)
        return NSScreen.screens.contains { $0.frame.intersects(rect) }
    }

    private func persistOriginIfOnScreen() {
        guard let panel else { return }
        let origin = panel.frame.origin
        guard isOnScreen(origin) else { return }
        Preferences.shared.floatingWidgetOrigin = origin
    }
}
