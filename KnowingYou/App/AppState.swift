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

    private var session: RecordingSession?
    private var eventTask: Task<Void, Never>?

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    /// Manual start (S11). S13 will add the auto/confirm-prompted path from
    /// meeting detection, reusing this same session-construction logic.
    func startManualRecording() async {
        guard case .idle = phase else { return }
        lastError = nil

        let micStatus = await Permissions.shared.request(.microphone)
        guard micStatus == .granted else {
            lastError = .permissionDenied(.microphone)
            AppLog.recording.error("manual recording blocked: microphone permission \(micStatus == .denied ? "denied" : "not determined", privacy: .public)")
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
        // RecordingNaming.manualSourceAppKey is a stable key for future localization
        // (S19); until there's a real strings table, every other UI string in this
        // app is a literal Chinese string too, so match that pattern here.
        let sourceApp = "手动录音"
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
        } catch {
            AppLog.recording.error("manual recording failed to start: \(error, privacy: .public)")
            lastError = (error as? KYError) ?? .audioDeviceUnavailable("\(error)")
            eventTask?.cancel()
            eventTask = nil
            session = nil
            phase = .idle
        }
    }

    func stopRecording() async {
        guard let session, case .recording(let info) = phase else { return }
        phase = .finalizing(info)
        do {
            _ = try await session.stop()
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
    }

    private func handle(_ event: RecordingSession.Event) {
        switch event {
        case .state:
            break // start()/stop() already drive `phase`; session-internal states aren't surfaced separately in v1 UI.
        case .level(let mic, let system):
            micLevel = mic
            systemLevel = system
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
