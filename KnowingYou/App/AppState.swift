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
            phase = .idle
        }
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
        do {
            let finalURL = try await session.stop()
            Notifier.shared.send(recordingSaved: finalURL)
        } catch {
            AppLog.recording.error("recording failed to finalize: \(error, privacy: .public)")
            lastError = error as? KYError
        }
        eventTask?.cancel()
        eventTask = nil
        self.session = nil
        elapsed = 0
        micLevel = 0
        systemLevel = 0
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
        case .deviceEvent(let message):
            AppLog.recording.info("device event: \(message, privacy: .public)")
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
