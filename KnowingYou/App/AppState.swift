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

    /// Installed by `MeetingCoordinator.start()`: lets a manual "开始录音"
    /// pick up the currently-detected meeting app's name instead of always
    /// falling back to "手动录音" (plan §5.3 / S13's scope).
    var resolveManualRecordingSourceApp: (() async -> String)?

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

    /// Manual start from the popover (S11). Resolves a source-app name (a
    /// currently-detected meeting app if any, via `resolveManualRecordingSourceApp`,
    /// else "手动录音") and defers to `startRecording(sourceApp:)`, the same
    /// path S13's `MeetingCoordinator` uses for auto/confirmed starts.
    func startManualRecording() async {
        let sourceApp = await resolveManualRecordingSourceApp?() ?? "手动录音"
        await startRecording(sourceApp: sourceApp)
    }

    func startRecording(sourceApp: String) async {
        guard case .idle = phase else { return }
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
        let info = RecordingInfo(baseName: baseName, directory: directory, startedAt: startedAt, sourceApp: sourceApp)
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

    /// E12 in the notes window. Real capture is S18's job — until then this
    /// just records that the feature isn't wired up yet, per this spec's scope.
    func captureScreenshotMark() {
        notesStore?.addEvent("截图功能未就绪", at: .now)
        AppLog.recording.info("screenshot mark requested before S18 implements real capture")
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
    /// Sets `.meetingActive(signal)` (a whitelisted app is using the mic,
    /// no recording yet), or clears back to `.idle` when passed `nil`. A
    /// no-op if a recording is already in progress or finalizing — the
    /// coordinator never calls this while `isCurrentlyRecording`.
    func setMeetingActive(_ signal: MeetingSignal?)
    func startRecording(sourceApp: String) async
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
