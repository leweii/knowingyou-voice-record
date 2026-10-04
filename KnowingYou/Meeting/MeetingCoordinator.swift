import Foundation

/// Turns `MeetingDetector.updates` into user-visible behavior: debounced
/// entry into "meeting active," auto-record vs. ask-first, debounced auto-
/// stop, and the once-per-meeting / manual-override rules from plan §5.1.
@MainActor
final class MeetingCoordinator {
    struct Timing: Sendable {
        var activateAfter: TimeInterval = 3
        var endAfter: TimeInterval = 1
    }

    private let detector: MeetingDetector
    private let appState: any MeetingRecordingControlling
    private let notifier: any MeetingNotifying
    private let prefs: Preferences
    private let clock: any Clock<Duration>
    private let timing: Timing

    private var updatesTask: Task<Void, Never>?
    /// The one meeting the coordinator is currently tracking end-to-end
    /// (either just "meetingActive" awaiting a decision, or actively
    /// recording). Only one at a time — "多个应用同时用麦克风取最早的一个".
    private var currentSignal: MeetingSignal?
    private var isCurrentlyRecording = false

    private var activationTasks: [String: Task<Void, Never>] = [:]
    private var deactivationTask: Task<Void, Never>?

    /// bundleIDPrefix → this meeting has already been acted on once (an
    /// auto-record started, or the "要开始录音吗？" prompt was shown). Whatever
    /// the user does next — start, dismiss, or stop a recording manually —
    /// the same meeting never prompts or auto-records again. Cleared only once
    /// that app has stopped using the mic for a full `endAfter` grace period
    /// (the same window that ends a meeting), so a brief mic blip mid-call
    /// doesn't turn into a "new meeting" and a second prompt.
    private var handledBundleIDs: Set<String> = []
    private var handledClearTasks: [String: Task<Void, Never>] = [:]

    init(
        detector: MeetingDetector,
        appState: any MeetingRecordingControlling,
        notifier: any MeetingNotifying = Notifier.shared,
        prefs: Preferences = .shared,
        clock: any Clock<Duration> = ContinuousClock(),
        timing: Timing = .init()
    ) {
        self.detector = detector
        self.appState = appState
        self.notifier = notifier
        self.prefs = prefs
        self.clock = clock
        self.timing = timing
    }

    func start() async {
        notifier.onAction = { [weak self] action, signal in
            self?.userDidRespond(action, for: signal)
        }
        appState.onUserInitiatedStop = { [weak self] in
            self?.handleUserInitiatedStop()
        }
        appState.resolveManualRecordingSourceApp = { [weak self] in
            guard let self else { return (name: "手动录音", bundleIDPrefix: nil) }
            let snapshot = await self.detector.snapshot()
            guard let first = snapshot.first else { return (name: "手动录音", bundleIDPrefix: nil) }
            return (name: first.app.displayNameKey, bundleIDPrefix: first.app.bundleIDPrefix)
        }

        await detector.start()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await activeUsers in self.detector.updates {
                self.handle(activeUsers)
            }
        }
    }

    func stop() async {
        updatesTask?.cancel()
        updatesTask = nil
        await detector.stop()
        for task in activationTasks.values { task.cancel() }
        activationTasks.removeAll()
        deactivationTask?.cancel()
        deactivationTask = nil
        for task in handledClearTasks.values { task.cancel() }
        handledClearTasks.removeAll()
    }

    /// Routes a notification action tap (`Notifier.onAction`) back into the
    /// state machine. Public per this spec's sketch, so it can also be
    /// driven directly by tests.
    func userDidRespond(_ action: NotificationAction, for signal: MeetingSignal) {
        guard currentSignal == signal else { return } // stale action from an already-ended meeting
        switch action {
        case .startRecording:
            isCurrentlyRecording = true
            Task { await appState.startRecording(sourceApp: signal.app.displayNameKey, sourceBundleIDPrefix: signal.app.bundleIDPrefix) }
        case .ignore:
            break
        }
    }

    // MARK: - Detector event handling

    private func handle(_ activeUsers: [MeetingDetector.ActiveMicUser]) {
        let activeKeys = Set(activeUsers.map(\.app.bundleIDPrefix))

        for key in Array(activationTasks.keys) where !activeKeys.contains(key) {
            activationTasks[key]?.cancel()
            activationTasks[key] = nil
        }

        if currentSignal == nil {
            for user in activeUsers where activationTasks[user.app.bundleIDPrefix] == nil {
                let key = user.app.bundleIDPrefix
                activationTasks[key] = Task { [weak self] in
                    guard let self else { return }
                    try? await self.clock.sleep(for: Self.duration(self.timing.activateAfter))
                    guard !Task.isCancelled else { return }
                    self.activationTasks[key] = nil
                    self.activate(user)
                }
            }
        }

        if let currentSignal, !activeKeys.contains(currentSignal.app.bundleIDPrefix) {
            if deactivationTask == nil {
                deactivationTask = Task { [weak self] in
                    guard let self else { return }
                    try? await self.clock.sleep(for: Self.duration(self.timing.endAfter))
                    guard !Task.isCancelled else { return }
                    await self.deactivate()
                }
            }
        } else {
            deactivationTask?.cancel()
            deactivationTask = nil
        }

        for key in Array(handledBundleIDs) {
            if activeKeys.contains(key) {
                handledClearTasks[key]?.cancel()
                handledClearTasks[key] = nil
            } else if handledClearTasks[key] == nil {
                handledClearTasks[key] = Task { [weak self] in
                    guard let self else { return }
                    try? await self.clock.sleep(for: Self.duration(self.timing.endAfter))
                    guard !Task.isCancelled else { return }
                    self.handledBundleIDs.remove(key)
                    self.handledClearTasks[key] = nil
                }
            }
        }
    }

    private func activate(_ user: MeetingDetector.ActiveMicUser) {
        guard currentSignal == nil else { return }
        let signal = MeetingSignal(app: user.app, pids: user.pids, since: .now)
        currentSignal = signal

        let key = user.app.bundleIDPrefix
        guard !handledBundleIDs.contains(key) else {
            // Same meeting we already prompted for / auto-recorded: only
            // reflect it in the UI state, never prompt or record again.
            appState.setMeetingActive(signal)
            return
        }
        handledBundleIDs.insert(key)

        if prefs.autoRecord && user.app.kind == .native {
            isCurrentlyRecording = true
            Task { await appState.startRecording(sourceApp: user.app.displayNameKey, sourceBundleIDPrefix: user.app.bundleIDPrefix) }
        } else {
            appState.setMeetingActive(signal)
            notifier.send(meetingDetected: signal)
        }
    }

    private func deactivate() async {
        guard let signal = currentSignal else { return }
        let wasRecording = isCurrentlyRecording
        currentSignal = nil
        isCurrentlyRecording = false
        deactivationTask = nil

        if wasRecording {
            await appState.stopRecordingInitiatedByCoordinator()
            notifier.send(meetingEnded: signal.app.displayNameKey)
        } else {
            appState.setMeetingActive(nil)
        }
    }

    /// The user pressed "停止录音" in the popover directly, bypassing us.
    /// The meeting is already in `handledBundleIDs`, so it won't prompt or
    /// restart while the same app is still talking (scenario ⑨ in this
    /// spec's acceptance criteria).
    private func handleUserInitiatedStop() {
        guard currentSignal != nil, isCurrentlyRecording else { return }
        currentSignal = nil
        isCurrentlyRecording = false
        deactivationTask?.cancel()
        deactivationTask = nil
    }

    private static func duration(_ seconds: TimeInterval) -> Duration {
        .seconds(seconds)
    }
}
