import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var phase: AppPhase = .idle
    var elapsed: TimeInterval = 0
    var micLevel: Float = 0
    var systemLevel: Float = 0
    var lastError: KYError?
    private(set) var isPaused = false
    private(set) var notesStore: NotesStore?

    /// `elapsed` minus total paused duration — freezes visually while
    /// paused since `elapsed` and the ongoing-pause duration grow at the
    /// same real-wall-clock rate (S16 decision record: `NoteEntry.offset`
    /// stays on real clock; only this *displayed* value subtracts pauses).
    var displayedElapsed: TimeInterval {
        let completed = pausedIntervals.reduce(0.0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
        let ongoing = currentPauseStart.map { Date.now.timeIntervalSince($0) } ?? 0
        return max(0, elapsed - completed - ongoing)
    }

    private var pausedIntervals: [ClosedRange<Date>] = []
    private var currentPauseStart: Date?
    /// True only when the *current* pause was auto-triggered by system
    /// sleep (S20 edge case #2) — distinguishes it from a manual E8 pause,
    /// so waking doesn't un-pause a recording the user paused on purpose.
    private var isPausedForSleep = false
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// Installed by `MeetingCoordinator.start()`: lets a manual "开始录音"
    /// pick up the currently-detected meeting app's name (and bundle ID
    /// prefix, for S18's screenshot window-matching) instead of always
    /// falling back to "手动录音" (plan §5.3 / S13's scope). **Note**: S13
    /// declared this property but never actually wired it up — S18 is the
    /// one that both fixes the wiring (see `MeetingCoordinator.start()`)
    /// and needs the bundle ID half of it, so it's documented here rather
    /// than pretending it was always complete.
    var resolveManualRecordingSourceApp: (() async -> (name: String, bundleIDPrefix: String?))?

    /// Installed by `MeetingCoordinator.start()`: fires when a recording
    /// ends via `stopRecording()` specifically — i.e. the user pressed
    /// "停止录音" themselves, not the coordinator's own auto-stop path
    /// (`stopRecordingInitiatedByCoordinator()`, which never touches this).
    /// This is how the coordinator learns "don't auto-resume for this still-
    /// talking app" (S13's decision record, scenario ⑨).
    var onUserInitiatedStop: (() -> Void)?

    private var session: RecordingSession?
    private var eventTask: Task<Void, Never>?

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    /// S20 edge case #2 (sleep → wake mid-recording): pauses on
    /// `willSleepNotification`, auto-resumes on `didWakeNotification`,
    /// reusing the same pause/resume machinery E8 uses. This was a genuine
    /// product decision with two other options on the table (see this
    /// spec's decision record for why "pause across the gap" won over
    /// "keep recording silence" or "stop and save").
    func startObservingSystemSleep() {
        guard sleepObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleSystemWillSleep() }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleSystemDidWake() }
        }
    }

    private func handleSystemWillSleep() async {
        guard case .recording = phase, !isPaused else { return }
        isPausedForSleep = true
        await pauseRecording()
    }

    private func handleSystemDidWake() async {
        guard isPausedForSleep else { return }
        isPausedForSleep = false
        await resumeRecording()
    }

    /// Manual start from the popover (S11). Resolves a source-app name (a
    /// currently-detected meeting app if any, via `resolveManualRecordingSourceApp`,
    /// else "手动录音") and defers to `startRecording(sourceApp:)`, the same
    /// path S13's `MeetingCoordinator` uses for auto/confirmed starts.
    func startManualRecording() async {
        let resolved = await resolveManualRecordingSourceApp?() ?? (name: "手动录音", bundleIDPrefix: nil)
        await startRecording(sourceApp: resolved.name, sourceBundleIDPrefix: resolved.bundleIDPrefix)
    }

    func startRecording(sourceApp: String, sourceBundleIDPrefix: String? = nil) async {
        // `.meetingActive` (S20 edge case #14: user manually clicks "开始录音"
        // in the popover in response to the orange dot / banner, instead of
        // waiting for or having denied the system notification) is just as
        // startable as `.idle` — only an already-running recording blocks a
        // new one.
        switch phase {
        case .idle, .meetingActive:
            break
        case .recording, .finalizing:
            return
        }
        lastError = nil

        let micStatus = await Permissions.shared.request(.microphone)
        guard micStatus == .granted else {
            lastError = .permissionDenied(.microphone)
            AppLog.recording.error("recording blocked: microphone permission \(micStatus == .denied ? "denied" : "not determined", privacy: .public)")
            return
        }

        do {
            try RecordingStore.shared.ensureWritable()
        } catch {
            lastError = (error as? KYError) ?? .saveDirectoryUnwritable(RecordingStore.shared.rootDirectory)
            return
        }

        let directory = RecordingStore.shared.rootDirectory
        let existing = Set(RecordingStore.shared.recordings.map(\.baseName))
        let startedAt = Date.now
        let baseName = RecordingNaming.baseName(startedAt: startedAt, sourceApp: sourceApp, existing: existing)
        let info = RecordingInfo(baseName: baseName, directory: directory, startedAt: startedAt, sourceApp: sourceApp, sourceBundleIDPrefix: sourceBundleIDPrefix)
        let notes = NotesStore(info: info)
        notesStore = notes
        FloatingWidgetPanel.shared.attachNotesStore(notes)

        let newSession = RecordingSession(config: .init(
            info: info,
            mic: Preferences.shared.micSelection,
            captureSystemAudio: Preferences.shared.captureSystemAudio,
            format: Preferences.shared.audioFormat
        ))
        session = newSession
        eventTask = Task { [weak self] in
            for await event in newSession.events {
                self?.handle(event)
            }
        }

        do {
            try await newSession.start()
            phase = .recording(info)
            if Preferences.shared.showFloatingWidget {
                FloatingWidgetPanel.shared.show()
            }
        } catch {
            AppLog.recording.error("recording failed to start: \(error, privacy: .public)")
            lastError = (error as? KYError) ?? .audioDeviceUnavailable("\(error)")
            eventTask?.cancel()
            eventTask = nil
            session = nil
            notesStore = nil
            phase = .idle
        }
    }

    /// E8 in the notes window (S16): pauses both audio capture and the
    /// visible timer, and drops a "暂停"/"继续" event entry into the notes.
    func togglePause() async {
        if isPaused {
            await resumeRecording()
        } else {
            await pauseRecording()
        }
    }

    private func pauseRecording() async {
        guard case .recording = phase, !isPaused, let session else { return }
        await session.pause()
        currentPauseStart = .now
        isPaused = true
        notesStore?.addEvent("暂停", at: .now)
        FloatingWidgetPanel.shared.updatePauseState(true)
    }

    private func resumeRecording() async {
        guard isPaused, let pauseStart = currentPauseStart, let session else { return }
        await session.resume()
        let range = pauseStart...Date.now
        pausedIntervals.append(range)
        notesStore?.recordPause(range)
        currentPauseStart = nil
        isPaused = false
        notesStore?.addEvent("继续", at: .now)
        FloatingWidgetPanel.shared.updatePauseState(false)
    }

    /// E11 in the notes window.
    func addMark() {
        notesStore?.addMark(at: .now)
    }

    /// The ⌥⌘M global hotkey (S17) — same effect as E11's toolbar button,
    /// just reachable without the notes window (or even the floating widget)
    /// being visible. A no-op when idle: `notesStore` is only non-nil while
    /// recording, so pressing the hotkey outside a recording does nothing.
    func quickMark() {
        addMark()
    }

    /// E12 in the notes window / ⌥⌘S. Silently does nothing while idle
    /// (`notesStore` is nil), same as `addMark`/`quickMark`.
    func captureScreenshotMark() {
        guard case .recording(let info) = phase else { return }
        let wallClock = Date.now
        Task {
            do {
                let path = try await ScreenshotMarker().capture(
                    for: info,
                    sourceBundleIDPrefix: info.sourceBundleIDPrefix,
                    at: wallClock
                )
                notesStore?.addScreenshot(path: path, at: wallClock)
            } catch {
                AppLog.recording.error("screenshot capture failed: \(error, privacy: .public)")
                notesStore?.addEvent("截图失败：\(Self.describeScreenshotFailure(error))", at: wallClock)
            }
        }
    }

    private static func describeScreenshotFailure(_ error: Error) -> String {
        if case KYError.permissionDenied = error {
            return "未获得屏幕录制权限"
        }
        if case ScreenshotMarker.CaptureError.noMatchingWindow = error {
            return "找不到可截取的窗口"
        }
        return "\(error)"
    }

    /// User-initiated stop (the popover's "停止录音" button). Fires
    /// `onUserInitiatedStop` — see that property's doc comment.
    func stopRecording() async {
        await stopRecording(notifyUserInitiated: true)
    }

    /// `MeetingCoordinator`'s auto-stop path (10s after the triggering
    /// process disappears). Identical to `stopRecording()` except it does
    /// NOT fire `onUserInitiatedStop`, since the coordinator already knows
    /// it's the one ending this recording.
    func stopRecordingInitiatedByCoordinator() async {
        await stopRecording(notifyUserInitiated: false)
    }

    private func stopRecording(notifyUserInitiated: Bool) async {
        guard let session, case .recording(let info) = phase else { return }
        phase = .finalizing(info)

        // Audio finalization and the notes file's final write don't depend
        // on each other — run them concurrently rather than serially.
        async let audioResult: Result<URL, Error> = {
            do { return .success(try await session.stop()) } catch { return .failure(error) }
        }()
        async let notesResult: Result<Void, Error> = {
            do { try await self.notesStore?.finish(endedAt: .now); return .success(()) } catch { return .failure(error) }
        }()

        switch await audioResult {
        case .success(let finalURL):
            Notifier.shared.send(recordingSaved: finalURL)
        case .failure(let error):
            AppLog.recording.error("recording failed to finalize: \(error, privacy: .public)")
            lastError = error as? KYError
        }
        if case .failure(let error) = await notesResult {
            AppLog.storage.error("notes failed to save: \(error, privacy: .public)")
        }

        eventTask?.cancel()
        eventTask = nil
        self.session = nil
        notesStore = nil
        elapsed = 0
        micLevel = 0
        systemLevel = 0
        isPaused = false
        pausedIntervals = []
        currentPauseStart = nil
        phase = .idle
        RecordingStore.shared.refresh()
        FloatingWidgetPanel.shared.hide()
        if notifyUserInitiated {
            onUserInitiatedStop?()
        }
    }

    private func handle(_ event: RecordingSession.Event) {
        switch event {
        case .state:
            break // start()/stop() already drive `phase`; session-internal states aren't surfaced separately in v1 UI.
        case .level(let mic, let system):
            micLevel = mic
            systemLevel = system
            FloatingWidgetPanel.shared.updateLevel(mic)
        case .elapsed(let value):
            elapsed = value
            FloatingWidgetPanel.shared.updateElapsed(displayedElapsed)
        case .deviceEvent(let message):
            AppLog.recording.info("device event: \(message, privacy: .public)")
            notesStore?.addEvent(message, at: .now)
        case .error(let error):
            AppLog.recording.error("session error: \(error, privacy: .public)")
            lastError = error
            if case .systemAudioTapFailed = error {
                // S20 edge case #11: system audio dropped out (or never
                // started) mid-recording — the mic keeps going, but the
                // user should see why the other side's audio is missing.
                notesStore?.addEvent("系统音频录制失败，本次录音仅包含麦克风声音", at: .now)
            }
            if case .diskFull = error {
                // S20 edge case #3: the session itself already stopped
                // trying to write. Finalize now so whatever's already on
                // disk gets transcoded and saved rather than left as a
                // dangling `.caf` until the user notices and hits stop.
                Task { await self.stopRecording() }
            }
        }
    }
}

/// The narrow surface `MeetingCoordinator` actually needs from `AppState`,
/// so `MeetingCoordinatorTests` can inject a fake instead of driving the
/// real recording pipeline (which needs microphone access this environment
/// can't grant — see S07/S09's decision records).
@MainActor
protocol MeetingRecordingControlling: AnyObject {
    var phase: AppPhase { get }
    var onUserInitiatedStop: (() -> Void)? { get set }
    var resolveManualRecordingSourceApp: (() async -> (name: String, bundleIDPrefix: String?))? { get set }
    /// Sets `.meetingActive(signal)` (a whitelisted app is using the mic,
    /// no recording yet), or clears back to `.idle` when passed `nil`. A
    /// no-op if a recording is already in progress or finalizing — the
    /// coordinator never calls this while `isCurrentlyRecording`.
    func setMeetingActive(_ signal: MeetingSignal?)
    func startRecording(sourceApp: String, sourceBundleIDPrefix: String?) async
    func stopRecordingInitiatedByCoordinator() async
}

extension AppState: MeetingRecordingControlling {
    func setMeetingActive(_ signal: MeetingSignal?) {
        switch phase {
        case .idle, .meetingActive:
            phase = signal.map(AppPhase.meetingActive) ?? .idle
        case .recording, .finalizing:
            break // never clobber an in-progress recording
        }
    }
}
