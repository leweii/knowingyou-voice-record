import AppKit
import SwiftUI

/// The floating widget (02-ui-spec.md §9/§10, plan §5.4): a single
/// `.nonactivatingPanel` that animates between a fixed-size 264×48 capsule
/// (S22) and
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
    private var markPulse = 0
    private var screenshotPulse = 0
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var commandDragMonitor: Any?

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
    private static let pillCornerRadius = PillView.size.height / 2
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
        hostingView?.cornerRadius = Self.pillCornerRadius
        applyFrame(for: PillView.size, panel: panel, display: false)
        positionAtDefaultOrRestoredOrigin(panel)
        rebuildContent()
        guard !KYMotion.reduceMotion else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        // Slide in from the right edge while fading up.
        let final = panel.frame.origin
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: final.x + 24, y: final.y))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = KYMotion.windowMorphDuration
            context.timingFunction = KYMotion.windowMorphTiming
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(final)
        }
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

    // MARK: - Feedback pulses (M6)

    /// Gold shockwave from the mark button / live dot — fired for both the
    /// toolbar button and the ⌥⌘M hotkey, so a hotkey press gets visible
    /// confirmation too.
    func pulseMark() {
        markPulse += 1
        guard hostingView != nil else { return }
        rebuildContent()
    }

    /// Shutter flash + viewfinder brackets after a screenshot mark lands.
    func pulseScreenshot() {
        screenshotPulse += 1
        guard hostingView != nil else { return }
        rebuildContent()
    }

    func expand() {
        guard let panel, !isExpanded else { return }
        isExpanded = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView?.isHidden = true
        // The pill needs this to be draggable by its background (it's one
        // small borderless blob with no title bar). The notes window has
        // large borderless text-input areas (title field, body) with no
        // visible bounds of their own — leaving this on meant a click meant
        // for "focus this text field" could be read as "drag the window"
        // instead, since AppKit treats an unclaimed mouseDown on window
        // background as a move gesture when this is true. That's the most
        // likely explanation for Jakob's "点击编辑没反应" report (2026-09-24
        // follow-up) surviving the `makeKey()` fix below: the window could
        // already accept keystrokes (paste worked), but clicks into the
        // SwiftUI-hosted fields weren't reliably reaching them as a focus
        // request. Turned off for the notes state; `collapse()` restores it.
        panel.isMovableByWindowBackground = false
        panel.styleMask.insert(.resizable)
        panel.minSize = Self.notesMinSize
        panel.maxSize = Self.notesMaxSize
        hostingView?.cornerRadius = KYRadius.floating
        rebuildContent() // renders NotesView while still hidden — no jitter
        let targetSize = Preferences.shared.notesWindowSize ?? NotesView.size
        applyFrame(for: targetSize, panel: panel, display: true) { [weak self, weak panel] in
            panel?.contentView?.isHidden = false
            self?.fadeContentIn()
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
        panel.isMovableByWindowBackground = true // restored — see expand()
        // Only the notes state is user-resizable — the pill is a fixed-size
        // status widget, not a window someone would want to drag-resize.
        panel.styleMask.remove(.resizable)
        hostingView?.cornerRadius = Self.pillCornerRadius
        rebuildContent() // renders PillView while still hidden — no jitter
        applyFrame(for: PillView.size, panel: panel, display: true) { [weak self, weak panel] in
            panel?.contentView?.isHidden = false
            self?.fadeContentIn()
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

        let hostingView = RoundedHostingView(rootView: FloatingWidgetContentView.placeholder, cornerRadius: Self.pillCornerRadius)
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

        // ⌘-drag anywhere in the widget moves it, even over the title field
        // and editor, where a plain drag has to select text instead. Lets the
        // notes window be pushed out of the way of the meeting from any spot.
        commandDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak panel] event in
            guard let panel, event.window === panel, event.modifierFlags.contains(.command) else { return event }
            panel.performDrag(with: event)
            return nil
        }

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func rebuildContent() {
        guard let hostingView else { return }
        let content: FloatingWidgetContentView.Content = isExpanded && currentNotesStore != nil
            ? .notes(store: currentNotesStore!, isPaused: currentIsPaused, micLevel: currentLevel, displayedElapsed: currentDisplayedElapsed)
            : .pill(level: currentLevel, displayedElapsed: currentDisplayedElapsed, isPaused: currentIsPaused)

        hostingView.rootView = FloatingWidgetContentView(
            content: content,
            markPulse: markPulse,
            screenshotPulse: screenshotPulse,
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
            // M3: a slight overshoot in the timing curve makes the capsule
            // "grow" into the notes window elastically, like the prototype.
            context.duration = KYMotion.reduceMotion ? 0.01 : KYMotion.windowMorphDuration
            context.timingFunction = KYMotion.windowMorphTiming
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.hostingView?.frame = NSRect(origin: .zero, size: size)
                completion?()
            }
        }
        hostingView?.frame = NSRect(origin: .zero, size: size)
    }

    /// Content is hidden during the frame animation (avoids SwiftUI relayout
    /// jitter mid-resize); bring it back with a short fade rather than a pop.
    private func fadeContentIn() {
        guard let hostingView, !KYMotion.reduceMotion else { return }
        hostingView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            hostingView.animator().alphaValue = 1
        }
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
        // Top-right, just under the menu bar — where the capsule reads as a
        // "dynamic island" for the recording, clear of most meeting UIs.
        let x = frame.maxX - PillView.size.width - 16
        let y = frame.maxY - PillView.size.height - 16
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
        case pill(level: Float, displayedElapsed: TimeInterval, isPaused: Bool)
        case notes(store: NotesStore, isPaused: Bool, micLevel: Float, displayedElapsed: TimeInterval)
    }

    let content: Content
    var markPulse: Int = 0
    var screenshotPulse: Int = 0
    var onExpand: () -> Void = {}
    var onCollapse: () -> Void = {}
    var onStop: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onMark: () -> Void = {}
    var onScreenshot: () -> Void = {}
    var onRevealInFinder: () -> Void = {}
    var onHideWidget: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    static var placeholder: FloatingWidgetContentView {
        FloatingWidgetContentView(content: .pill(level: 0, displayedElapsed: 0, isPaused: false))
    }

    var body: some View {
        stateView
            .overlay {
                WidgetFeedbackOverlay(
                    markPulse: markPulse,
                    screenshotPulse: screenshotPulse,
                    markOrigin: isPill ? UnitPoint(x: 0.08, y: 0.5) : UnitPoint(x: 0.82, y: 0.935),
                    cornerRadius: isPill ? PillView.size.height / 2 : KYRadius.floating
                )
            }
    }

    private var isPill: Bool {
        if case .pill = content { return true }
        return false
    }

    @ViewBuilder
    private var stateView: some View {
        switch content {
        case .pill(let level, let displayedElapsed, let isPaused):
            PillView(level: level, displayedElapsed: displayedElapsed, isPaused: isPaused, onExpand: onExpand, onStop: onStop)
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
