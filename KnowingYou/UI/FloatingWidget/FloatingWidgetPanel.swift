import AppKit
import SwiftUI

/// The floating widget (02-ui-spec.md §9/§10, plan §5.4): a single
/// `.nonactivatingPanel` that animates between a fixed-size 44×175 pill and
/// a notes window (default 418×380, now user-resizable within
/// `notesMinSize`...`notesMaxSize` — Jakob's real-Mac feedback, 2026-09-24),
/// anchored so its top-right corner never moves *during the expand/collapse
/// animation*. A live user drag-resize of the notes window can move any
/// edge, same as an ordinary resizable window — the anchor guarantee is only
/// about the programmatic pill⇄notes transition, not manual resizing (see
/// this spec's decision record). Never steals focus from a meeting app:
/// `orderFrontRegardless()`, never `makeKeyAndOrderFront`, and
/// `becomesKeyOnlyIfNeeded` in the notes state so it only becomes key once
/// the user actually clicks into the text area.
@MainActor
final class FloatingWidgetPanel {
    static let shared = FloatingWidgetPanel()

    private var panel: NSPanel?
    private var hostingView: RoundedHostingView<FloatingWidgetContentView>?

    private var onStop: () -> Void = {}
    private var onTogglePause: () -> Void = {}
    private var onMark: () -> Void = {}
    private var onScreenshot: () -> Void = {}
    private var onRevealInFinder: () -> Void = {}
    private var onOpenSettings: () -> Void = {}

    private var isExpanded = false
    private var currentLevel: Float = 0
    private var currentNotesStore: NotesStore?
    private var currentIsPaused = false
    private var currentDisplayedElapsed: TimeInterval = 0
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    /// User-draggable bounds for the notes window (Jakob's real-Mac feedback,
    /// 2026-09-24: "窗口大小需要可调整"). The pill never gets `.resizable` —
    /// only the expanded notes state does, toggled in `expand()`/`collapse()`.
    /// The original 340×300 let the window shrink smaller than its own fixed
    /// content actually needs — the toolbar alone (5×56pt buttons + spacing +
    /// padding) has an intrinsic minimum width around 410pt, and the fixed
    /// header/disclaimer/title/toolbar rows plus a usable amount of editor
    /// space need more than 300pt of height — so at the old minimum, content
    /// visibly overlapped/clipped (Jakob found this at min height, 2026-09-24
    /// follow-up). Raised to comfortably clear both.
    private static let notesMinSize = CGSize(width: 420, height: 360)
    private static let notesMaxSize = CGSize(width: 900, height: 800)

    /// Deliberately not constructed here — see S15's decision record:
    /// building an `NSPanel` at app-launch time crashed under the `xctest`
    /// host in this environment. Deferred to the first real `show()`.
    private init() {}

    func configure(
        onStop: @escaping () -> Void,
        onTogglePause: @escaping () -> Void = {},
        onMark: @escaping () -> Void = {},
        onScreenshot: @escaping () -> Void = {},
        onRevealInFinder: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.onStop = onStop
        self.onTogglePause = onTogglePause
        self.onMark = onMark
        self.onScreenshot = onScreenshot
        self.onRevealInFinder = onRevealInFinder
        self.onOpenSettings = onOpenSettings
    }

    // MARK: - Lifecycle

    func show() {
        let panel = ensurePanel()
        isExpanded = false
        applyFrame(for: PillView.size, panel: panel, display: false)
        positionAtDefaultOrRestoredOrigin(panel)
        panel.alphaValue = 1
        rebuildContent()
        panel.orderFrontRegardless()
    }

    func hide(animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        isExpanded = false
        currentNotesStore = nil
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
                panel.alphaValue = 1
                self?.rebuildContent()
            }
        }
    }

    /// "隐藏浮窗（本次录音）" (E2): just an `orderOut` — recording keeps
    /// running, the popover's stop button still works, and the widget
    /// doesn't reappear until the *next* recording starts.
    func hideForThisRecording() {
        panel?.orderOut(nil)
    }

    // MARK: - Pill <-> notes

    func attachNotesStore(_ store: NotesStore) {
        currentNotesStore = store
    }

    func expand() {
        guard let panel, !isExpanded else { return }
        isExpanded = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView?.isHidden = true
        panel.styleMask.insert(.resizable)
        panel.minSize = Self.notesMinSize
        panel.maxSize = Self.notesMaxSize
        rebuildContent() // renders NotesView while still hidden — no jitter
        let targetSize = Preferences.shared.notesWindowSize ?? NotesView.size
        applyFrame(for: targetSize, panel: panel, display: true) { [weak panel] in
            panel?.contentView?.isHidden = false
            // Jakob reported (2026-09-24) that clicking into the title field
            // or editor produced no typed text at all. `becomesKeyOnlyIfNeeded`
            // is supposed to let a click alone promote the panel to key
            // without this call, but that promotion is triggered by
            // AppKit's own `-mouseDown:` handling on the clicked view —
            // a SwiftUI `TextField` hosted via `NSHostingView` may not
            // reliably trigger it the same way a plain `NSTextField` would.
            // Making the panel key as soon as it finishes expanding removes
            // that dependency entirely: `-makeKey()` (unlike
            // `-makeKeyAndOrderFront:`) does not activate the app or steal
            // focus from whatever the user was doing, which is the whole
            // point of `.nonactivatingPanel` — it only makes *this* panel
            // able to receive keystrokes once something inside it is
            // clicked or focused.
            panel?.makeKey()
        }
    }

    func collapse() {
        guard let panel, isExpanded else { return }
        isExpanded = false
        panel.resignKey()
        panel.contentView?.isHidden = true
        // Only the notes state is user-resizable — the pill is a fixed-size
        // status widget, not a window someone would want to drag-resize.
        panel.styleMask.remove(.resizable)
        rebuildContent() // renders PillView while still hidden — no jitter
        applyFrame(for: PillView.size, panel: panel, display: true) { [weak panel] in
            panel?.contentView?.isHidden = false
        }
    }

    // MARK: - Live updates from AppState

    func updateLevel(_ level: Float) {
        currentLevel = level
        guard hostingView != nil else { return }
        rebuildContent()
    }

    func updateElapsed(_ displayedElapsed: TimeInterval) {
        currentDisplayedElapsed = displayedElapsed
        guard hostingView != nil else { return }
        rebuildContent()
    }

    func updatePauseState(_ isPaused: Bool) {
        currentIsPaused = isPaused
        guard hostingView != nil else { return }
        rebuildContent()
    }

    // MARK: - Panel construction

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

        let hostingView = RoundedHostingView(rootView: FloatingWidgetContentView.placeholder, cornerRadius: 12)
        hostingView.frame = NSRect(origin: .zero, size: PillView.size)
        panel.contentView = hostingView

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistOriginIfOnScreen() }
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistNotesWindowSizeIfExpanded() }
        }

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func rebuildContent() {
        guard let hostingView else { return }
        let content: FloatingWidgetContentView.Content = isExpanded && currentNotesStore != nil
            ? .notes(store: currentNotesStore!, isPaused: currentIsPaused, micLevel: currentLevel, displayedElapsed: currentDisplayedElapsed)
            : .pill(level: currentLevel)

        hostingView.rootView = FloatingWidgetContentView(
            content: content,
            onExpand: { [weak self] in self?.expand() },
            onCollapse: { [weak self] in self?.collapse() },
            onStop: { [weak self] in self?.onStop() },
            onTogglePause: { [weak self] in self?.onTogglePause() },
            onMark: { [weak self] in self?.onMark() },
            onScreenshot: { [weak self] in self?.onScreenshot() },
            onRevealInFinder: { [weak self] in self?.onRevealInFinder() },
            onHideWidget: { [weak self] in self?.hideForThisRecording() },
            onOpenSettings: { [weak self] in self?.onOpenSettings() }
        )
    }

    /// Resizes the panel while keeping its top-right corner fixed, per
    /// plan §5.4's anchoring requirement.
    private func applyFrame(for size: CGSize, panel: NSPanel, display: Bool, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let old = panel.frame
        let topRight = NSPoint(x: old.maxX, y: old.maxY)
        let newFrame = NSRect(
            x: topRight.x - size.width,
            y: topRight.y - size.height,
            width: size.width,
            height: size.height
        )
        guard display else {
            panel.setFrame(newFrame, display: false)
            hostingView?.frame = NSRect(origin: .zero, size: size)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.hostingView?.frame = NSRect(origin: .zero, size: size)
                completion?()
            }
        }
        hostingView?.frame = NSRect(origin: .zero, size: size)
    }

    private func positionAtDefaultOrRestoredOrigin(_ panel: NSPanel) {
        if let origin = Preferences.shared.floatingWidgetOrigin, isOnScreen(origin, size: PillView.size) {
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

    private func isOnScreen(_ origin: CGPoint, size: CGSize) -> Bool {
        let rect = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.frame.intersects(rect) }
    }

    private func persistOriginIfOnScreen() {
        guard let panel, !isExpanded else { return } // only the pill's position is meaningful to restore
        let origin = panel.frame.origin
        guard isOnScreen(origin, size: PillView.size) else { return }
        Preferences.shared.floatingWidgetOrigin = origin
    }

    /// `didEndLiveResizeNotification` also fires for the pill (nothing
    /// resizes it, but the notification is scoped to `object: panel` so it's
    /// harmless either way) — `isExpanded` gates so only a real user drag of
    /// the notes window persists a size.
    private func persistNotesWindowSizeIfExpanded() {
        guard let panel, isExpanded else { return }
        Preferences.shared.notesWindowSize = panel.frame.size
    }
}

/// Switches the shared hosting view between the pill and notes SwiftUI
/// content — one concrete `View` type so `RoundedHostingView` doesn't need
/// to be reconstructed (and re-clipped/re-layered) every time the widget
/// expands or collapses.
struct FloatingWidgetContentView: View {
    enum Content {
        case pill(level: Float)
        case notes(store: NotesStore, isPaused: Bool, micLevel: Float, displayedElapsed: TimeInterval)
    }

    let content: Content
    var onExpand: () -> Void = {}
    var onCollapse: () -> Void = {}
    var onStop: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onMark: () -> Void = {}
    var onScreenshot: () -> Void = {}
    var onRevealInFinder: () -> Void = {}
    var onHideWidget: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    static var placeholder: FloatingWidgetContentView { FloatingWidgetContentView(content: .pill(level: 0)) }

    var body: some View {
        switch content {
        case .pill(let level):
            PillView(level: level, onExpand: onExpand, onStop: onStop)
        case .notes(let store, let isPaused, let micLevel, let displayedElapsed):
            NotesView(
                notesStore: store,
                isPaused: isPaused,
                micLevel: micLevel,
                displayedElapsed: displayedElapsed,
                onCollapse: onCollapse,
                onRevealInFinder: onRevealInFinder,
                onHideWidget: onHideWidget,
                onOpenSettings: onOpenSettings,
                onTogglePause: onTogglePause,
                onStop: onStop,
                onMark: onMark,
                onScreenshot: onScreenshot
            )
        }
    }
}
