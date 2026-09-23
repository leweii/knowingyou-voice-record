import Foundation

/// Turns `MeetingDetector.updates` into user-visible behavior: debounced
/// entry into "meeting active," auto-record vs. ask-first, debounced auto-
/// stop, and the "本次会议不再提示" / manual-override rules from plan §5.1.
@MainActor
final class MeetingCoordinator {
    struct Timing: Sendable {
        var activateAfter: TimeInterval = 3
        var endAfter: TimeInterval = 10
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

    /// bundleIDPrefix → "本次会议不再提示"; cleared once that process disappears.
    private var silencedBundleIDs: Set<String> = []
    /// bundleIDPrefix → user manually stopped a coordinator-started recording
    /// while the app was still talking; cleared once that process disappears.
    private var suppressedAutoRecordBundleIDs: Set<String> = []

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
    }

    /// Routes a notification action tap (`Notifier.onAction`) back into the
    /// state machine. Public per this spec's sketch, so it can also be
    /// driven directly by tests.
    func userDidRespond(_ action: NotificationAction, for signal: MeetingSignal) {
        guard currentSignal == signal else { return } // stale action from an already-ended meeting
        switch action {
        case .startRecording:
            isCurrentlyRecording = true
            Task { await appState.startRecording(sourceApp: signal.app.displayNameKey) }
        case .ignoreThisMeeting:
            silencedBundleIDs.insert(signal.app.bundleIDPrefix)
            currentSignal = nil
            appState.setMeetingActive(nil)
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

        for key in Array(silencedBundleIDs) where !activeKeys.contains(key) {
            silencedBundleIDs.remove(key)
        }
        for key in Array(suppressedAutoRecordBundleIDs) where !activeKeys.contains(key) {
            suppressedAutoRecordBundleIDs.remove(key)
        }
    }

    private func activate(_ user: MeetingDetector.ActiveMicUser) {
        guard currentSignal == nil else { return }
        let signal = MeetingSignal(app: user.app, pids: user.pids, since: .now)
        currentSignal = signal

        let shouldAutoRecord = prefs.autoRecord
            && user.app.kind == .native
            && !suppressedAutoRecordBundleIDs.contains(user.app.bundleIDPrefix)

        if shouldAutoRecord {
            isCurrentlyRecording = true
            Task { await appState.startRecording(sourceApp: user.app.displayNameKey) }
        } else {
            appState.setMeetingActive(signal)
            if !silencedBundleIDs.contains(user.app.bundleIDPrefix) {
                notifier.send(meetingDetected: signal)
            }
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
    /// If that recording was one we auto-started, remember not to
    /// immediately restart it while the same app is still talking
    /// (scenario ⑨ in this spec's acceptance criteria).
    private func handleUserInitiatedStop() {
        guard let signal = currentSignal, isCurrentlyRecording else { return }
        suppressedAutoRecordBundleIDs.insert(signal.app.bundleIDPrefix)
        currentSignal = nil
        isCurrentlyRecording = false
        deactivationTask?.cancel()
        deactivationTask = nil
    }

    private static func duration(_ seconds: TimeInterval) -> Duration {
        .seconds(seconds)
    }
}
