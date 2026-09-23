import Foundation
import Testing
@testable import KnowingYou

/// A `Clock` whose `now` only advances when the test explicitly calls
/// `advance(by:)` — lets `MeetingCoordinatorTests` exercise the 3s/10s
/// debounce timers without ever really waiting (per this spec's "不要
/// Task.sleep 真等" instruction).
private final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration = .zero
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
        static func == (lhs: Instant, rhs: Instant) -> Bool { lhs.offset == rhs.offset }
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
    }

    private let lock = NSLock()
    private var currentInstant = Instant()
    private var waiters: [(deadline: Instant, continuation: CheckedContinuation<Void, Never>)] = []

    var now: Instant {
        lock.lock()
        defer { lock.unlock() }
        return currentInstant
    }

    var minimumResolution: Duration { .nanoseconds(1) }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if deadline <= currentInstant {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append((deadline, continuation))
            lock.unlock()
        }
    }

    /// Advances time and resumes any sleepers whose deadline has now passed.
    func advance(by duration: Duration) {
        lock.lock()
        currentInstant = currentInstant.advanced(by: duration)
        let ready = waiters.filter { $0.deadline <= currentInstant }
        waiters.removeAll { $0.deadline <= currentInstant }
        lock.unlock()
        for waiter in ready { waiter.continuation.resume() }
    }
}

/// Records calls instead of driving a real `RecordingSession` — the real
/// `AppState` needs microphone access this environment can't grant (S07's
/// decision record), so `MeetingCoordinator` depends on the narrow
/// `MeetingRecordingControlling` protocol instead of the concrete type.
@MainActor
private final class FakeRecordingControl: MeetingRecordingControlling {
    private(set) var phase: AppPhase = .idle
    var onUserInitiatedStop: (() -> Void)?
    private(set) var startCalls: [String] = []
    private(set) var coordinatorStopCount = 0
    private(set) var meetingActiveSignals: [MeetingSignal?] = []

    func setMeetingActive(_ signal: MeetingSignal?) {
        meetingActiveSignals.append(signal)
        switch phase {
        case .idle, .meetingActive:
            phase = signal.map(AppPhase.meetingActive) ?? .idle
        case .recording, .finalizing:
            break
        }
    }

    func startRecording(sourceApp: String) async {
        startCalls.append(sourceApp)
        phase = .recording(RecordingInfo(baseName: "fake", directory: FileManager.default.temporaryDirectory, startedAt: .now, sourceApp: sourceApp))
    }

    func stopRecordingInitiatedByCoordinator() async {
        coordinatorStopCount += 1
        phase = .idle
    }

    /// Simulates the user pressing "停止录音" in the popover directly,
    /// bypassing the coordinator entirely.
    func simulateUserInitiatedStop() {
        phase = .idle
        onUserInitiatedStop?()
    }
}

@MainActor
private final class FakeNotifier: MeetingNotifying {
    var onAction: ((NotificationAction, MeetingSignal) -> Void)?
    private(set) var meetingDetectedSignals: [MeetingSignal] = []
    private(set) var meetingEndedNames: [String] = []

    func send(meetingDetected signal: MeetingSignal) {
        meetingDetectedSignals.append(signal)
    }

    func send(meetingEnded appDisplayName: String) {
        meetingEndedNames.append(appDisplayName)
    }
}

private final class FakeProcessObjectReader: ProcessObjectReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [(pid: pid_t, bundleID: String)] = []

    func set(_ results: [(pid: pid_t, bundleID: String)]) {
        lock.lock()
        defer { lock.unlock() }
        self.results = results
    }

    func activeInputProcesses() -> [(pid: pid_t, bundleID: String)] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

private let zoom = KnownApp(bundleIDPrefix: "us.zoom.xos", displayNameKey: "Zoom", kind: .native, isEnabled: true)
private let chrome = KnownApp(bundleIDPrefix: "com.google.Chrome", displayNameKey: "Chrome", kind: .browser, isEnabled: true)

@MainActor
private struct Harness {
    let clock = ManualClock()
    let reader = FakeProcessObjectReader()
    let control = FakeRecordingControl()
    let notifier = FakeNotifier()
    let prefs: Preferences
    let detector: MeetingDetector
    let coordinator: MeetingCoordinator

    init(autoRecord: Bool, apps: [KnownApp] = [zoom, chrome]) {
        let defaults = UserDefaults(suiteName: "MeetingCoordinatorTests-\(UUID().uuidString)")!
        prefs = Preferences(defaults: defaults)
        prefs.autoRecord = autoRecord
        let capturedApps = apps
        detector = MeetingDetector(apps: { capturedApps }, reader: reader)
        coordinator = MeetingCoordinator(detector: detector, appState: control, notifier: notifier, prefs: prefs, clock: clock)
    }

    /// Forces the detector to notice `reader`'s current state immediately
    /// (bypassing its real 2s poll timer) and lets the coordinator's
    /// `for await` consumer loop process the resulting event before
    /// returning — see this spec's decision record on why a few real
    /// `Task.yield()`s are an acceptable settling mechanism here, unlike the
    /// 3s/10s state-machine delays the `ManualClock` exists to avoid.
    func pushDetectorUpdate() async {
        _ = await detector.snapshot()
        for _ in 0..<10 { await Task.yield() }
    }

    func advanceClock(_ duration: Duration) async {
        clock.advance(by: duration)
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor
struct MeetingCoordinatorTests {
    @Test func processDisappearingBeforeThreeSecondsNeverActivates() async {
        let h = Harness(autoRecord: false)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(2))

        h.reader.set([])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(5))

        #expect(h.control.startCalls.isEmpty)
        if case .idle = h.control.phase {} else { Issue.record("expected idle, got \(h.control.phase)") }
    }

    @Test func threeSecondsWithAutoRecordOffSendsNotificationOnly() async {
        let h = Harness(autoRecord: false)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))

        #expect(h.control.startCalls.isEmpty)
        #expect(h.notifier.meetingDetectedSignals.map(\.app.displayNameKey) == ["Zoom"])
    }

    @Test func threeSecondsWithAutoRecordOnStartsRecordingDirectly() async {
        let h = Harness(autoRecord: true)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))

        #expect(h.control.startCalls == ["Zoom"])
    }

    @Test func browserWithAutoRecordOnOnlyNotifiesNeverAutoRecords() async {
        let h = Harness(autoRecord: true, apps: [chrome])
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "com.google.Chrome")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))

        #expect(h.control.startCalls.isEmpty)
    }

    @Test func recordingSurvivesAnEightSecondGap() async {
        let h = Harness(autoRecord: true)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.control.startCalls == ["Zoom"])

        h.reader.set([])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(8))
        #expect(h.control.coordinatorStopCount == 0)

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(5)) // well past the original 10s mark, but the gap was cancelled
        #expect(h.control.coordinatorStopCount == 0)
    }

    @Test func tenSecondGapStopsAndFinalizes() async {
        let h = Harness(autoRecord: true)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.control.startCalls == ["Zoom"])

        h.reader.set([])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(10))

        #expect(h.control.coordinatorStopCount == 1)
        if case .idle = h.control.phase {} else { Issue.record("expected idle after auto-stop, got \(h.control.phase)") }
        #expect(h.notifier.meetingEndedNames == ["Zoom"])
    }

    @Test func userRespondingStartRecordingFromNotificationStartsRecording() async {
        let h = Harness(autoRecord: false)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.control.startCalls.isEmpty)

        guard let signal = h.notifier.meetingDetectedSignals.last else {
            Issue.record("expected a meetingDetected notification to have been sent")
            return
        }
        h.coordinator.userDidRespond(.startRecording, for: signal)
        await Task.yield()

        #expect(h.control.startCalls == ["Zoom"])
    }

    @Test func ignoreThisMeetingSuppressesFurtherNotificationsForThatProcess() async {
        let h = Harness(autoRecord: false)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        guard let signal = h.notifier.meetingDetectedSignals.last else {
            Issue.record("expected a meetingDetected notification to have been sent")
            return
        }
        #expect(h.notifier.meetingDetectedSignals.count == 1)

        h.coordinator.userDidRespond(.ignoreThisMeeting, for: signal)
        await Task.yield()

        // Same process, still talking, detector re-emits (e.g. after a
        // device-list churn) — must not notify again.
        h.reader.set([(pid: 1, bundleID: "us.zoom.xos"), (pid: 99, bundleID: "us.zoom.xos")]) // still Zoom, different pid set
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.notifier.meetingDetectedSignals.count == 1) // unchanged

        // Once the process actually disappears for a full 10s grace period
        // (not just a brief blip — see `recordingSurvivesAnEightSecondGap`
        // for why a short gap alone must NOT count as "gone") and a new one
        // starts, it's a new meeting — notifications resume.
        h.reader.set([])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(10))
        h.reader.set([(pid: 2, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.notifier.meetingDetectedSignals.count == 2)
    }

    @Test func manualStopSuppressesAutoRecordWhileStillTalking() async {
        let h = Harness(autoRecord: true)
        await h.coordinator.start()

        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.control.startCalls == ["Zoom"])

        // User presses "停止录音" directly (not via coordinator auto-stop).
        h.control.simulateUserInitiatedStop()
        await Task.yield()

        // Same app is still talking — must not immediately restart.
        h.reader.set([(pid: 1, bundleID: "us.zoom.xos")]) // no-op change, still present
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.control.startCalls == ["Zoom"]) // unchanged: no second start call

        // Only once the app actually disappears and a fresh session begins
        // does the suppression clear.
        h.reader.set([])
        await h.pushDetectorUpdate()
        h.reader.set([(pid: 2, bundleID: "us.zoom.xos")])
        await h.pushDetectorUpdate()
        await h.advanceClock(.seconds(3))
        #expect(h.control.startCalls == ["Zoom", "Zoom"])
    }
}
