import AppKit
import SwiftUI

/// The borderless panel that hosts `PopoverView` (02-ui-spec.md §8). Not an
/// `NSPopover` (no arrow, custom corner radius); a plain `.nonactivatingPanel`
/// so clicking it never steals keyboard focus from whatever meeting app is
/// in front — see this spec's decision record.
@MainActor
final class PopoverPanel {
    static let baseSize = NSSize(width: PopoverView.width, height: 188)

    private let panel: NSPanel
    private let hostingView: NSHostingView<PopoverView>
    private weak var statusItem: NSStatusItem?
    private var outsideClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var spaceChangeObserver: NSObjectProtocol?
    private var trackingTask: Task<Void, Never>?

    init(appState: AppState, statusItem: NSStatusItem, onOpenSaveDirectory: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.statusItem = statusItem

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.baseSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // Built with no-op closures first: capturing `self` in a closure
        // before every stored property is set would fail definite-init
        // checking, even weakly. The real closures (which need `self.close()`)
        // are wired in below, once `self` is fully initialized.
        hostingView = RoundedHostingView(rootView: PopoverView(appState: appState, onOpenSaveDirectory: {}, onOpenSettings: {}))
        hostingView.frame = NSRect(origin: .zero, size: Self.baseSize)
        panel.contentView = hostingView

        hostingView.rootView = PopoverView(
            appState: appState,
            onOpenSaveDirectory: { [weak self] in
                onOpenSaveDirectory()
                self?.close()
            },
            onOpenSettings: { [weak self] in
                onOpenSettings()
                self?.close()
            }
        )

        trackContentSize()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible {
            close()
        } else {
            open()
        }
    }

    func close() {
        panel.orderOut(nil)
        stopMonitoringOutsideInteraction()
    }

    private func open() {
        resizeToFitContent()
        positionPanel()
        panel.orderFrontRegardless() // never makeKey: would steal focus from a meeting app in front
        startMonitoringOutsideInteraction()
    }

    private func positionPanel() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main
        var origin = NSPoint(
            x: buttonFrame.maxX - panel.frame.width,
            y: buttonFrame.minY - panel.frame.height - 4
        )
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
        }
        panel.setFrameOrigin(origin)
    }

    /// Re-observes `PopoverView`'s natural size (driven by the recent-recordings
    /// disclosure and the "now recording" filename row) whenever the
    /// underlying state it depends on changes, so the panel grows/shrinks to
    /// match rather than clipping or leaving dead space.
    private func trackContentSize() {
        trackingTask = Task { [weak self] in
            var lastHeight: CGFloat = Self.baseSize.height
            while !Task.isCancelled {
                guard let self else { return }
                if self.panel.isVisible {
                    let height = self.hostingView.fittingSize.height
                    if abs(height - lastHeight) > 0.5 {
                        lastHeight = height
                        self.resizeToFitContent()
                    }
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func resizeToFitContent() {
        let fitting = hostingView.fittingSize
        let newHeight = max(fitting.height, Self.baseSize.height)
        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size.width = Self.baseSize.width
        frame.size.height = newHeight
        frame.origin.y = topEdge - newHeight
        panel.setFrame(frame, display: panel.isVisible)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func startMonitoringOutsideInteraction() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in self?.close() }
                return nil
            }
            return event
        }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func stopMonitoringOutsideInteraction() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let spaceChangeObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver) }
        outsideClickMonitor = nil
        localKeyMonitor = nil
        spaceChangeObserver = nil
    }
}

/// Clips the hosting view's content to the 14pt rounded rect the spec calls
/// for, since the panel itself is borderless/transparent with no native
/// corner radius of its own.
private final class RoundedHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureLayer()
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }
}
