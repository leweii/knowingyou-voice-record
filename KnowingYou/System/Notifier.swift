import AppKit
import UserNotifications

/// The two notification sends `MeetingCoordinator` itself triggers, factored
/// out so `MeetingCoordinatorTests` can inject a fake that records calls
/// instead of touching the real `UNUserNotificationCenter` (S12/S09
/// established this "protocol-ize the one dependency you need to fake"
/// pattern already).
@MainActor
protocol MeetingNotifying: AnyObject {
    var onAction: ((NotificationAction, MeetingSignal) -> Void)? { get set }
    func send(meetingDetected signal: MeetingSignal)
    func send(meetingEnded appDisplayName: String)
}

/// Wraps `UNUserNotificationCenter`: registers the three category/action
/// sets declared in S00 (`NotificationCategory`/`NotificationAction`), sends
/// each of the three notification kinds `MeetingCoordinator`/`AppState` need,
/// and routes action taps back via `onAction`.
@MainActor
final class Notifier: NSObject, MeetingNotifying {
    static let shared = Notifier()

    /// `MeetingCoordinator.start()` installs this to receive action taps on
    /// `MEETING_DETECTED` notifications, keyed back to the `MeetingSignal`
    /// that triggered them.
    var onAction: ((NotificationAction, MeetingSignal) -> Void)?

    private var pendingSignals: [String: MeetingSignal] = [:]
    private var expiryTasks: [String: Task<Void, Never>] = [:]

    func registerCategories() {
        let start = UNNotificationAction(identifier: NotificationAction.startRecording.rawValue, title: String(localized: "开始录音"), options: [.foreground])
        let ignoreThisMeeting = UNNotificationAction(identifier: NotificationAction.ignoreThisMeeting.rawValue, title: String(localized: "本次会议不再提示"), options: [])
        let ignore = UNNotificationAction(identifier: NotificationAction.ignore.rawValue, title: String(localized: "忽略"), options: [])

        let meetingDetected = UNNotificationCategory(
            identifier: NotificationCategory.meetingDetected.rawValue,
            actions: [start, ignoreThisMeeting, ignore],
            intentIdentifiers: [],
            options: []
        )
        let meetingEnded = UNNotificationCategory(identifier: NotificationCategory.meetingEnded.rawValue, actions: [], intentIdentifiers: [], options: [])
        let recordingSaved = UNNotificationCategory(identifier: NotificationCategory.recordingSaved.rawValue, actions: [], intentIdentifiers: [], options: [])

        UNUserNotificationCenter.current().setNotificationCategories([meetingDetected, meetingEnded, recordingSaved])
        UNUserNotificationCenter.current().delegate = self
    }

    func send(meetingDetected signal: MeetingSignal) {
        guard Preferences.shared.notifyMeetingDetected else { return }
        let id = "meeting-detected-\(signal.app.bundleIDPrefix)-\(signal.since.timeIntervalSince1970)"
        pendingSignals[id] = signal

        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "检测到%@开始使用麦克风"), signal.app.displayNameKey)
        content.body = String(localized: "要开始录音吗？")
        content.categoryIdentifier = NotificationCategory.meetingDetected.rawValue
        content.userInfo = ["requestID": id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))

        expiryTasks[id]?.cancel()
        expiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            self?.pendingSignals[id] = nil
            self?.expiryTasks[id] = nil
        }
    }

    func send(meetingEnded appDisplayName: String) {
        guard Preferences.shared.notifyMeetingEnded else { return }
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "%@会议已结束"), appDisplayName)
        content.categoryIdentifier = NotificationCategory.meetingEnded.rawValue
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func send(recordingSaved audioURL: URL) {
        guard Preferences.shared.notifyRecordingSaved else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "录音已保存")
        content.body = audioURL.lastPathComponent
        content.categoryIdentifier = NotificationCategory.recordingSaved.rawValue
        content.userInfo = ["audioPath": audioURL.path]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func handleAction(identifier: String, requestID: String?) {
        guard let requestID, let signal = pendingSignals[requestID] else { return }
        let action: NotificationAction
        switch identifier {
        case NotificationAction.startRecording.rawValue, UNNotificationDefaultActionIdentifier:
            action = .startRecording
        case NotificationAction.ignoreThisMeeting.rawValue:
            action = .ignoreThisMeeting
        default:
            action = .ignore
        }
        onAction?(action, signal)
        pendingSignals[requestID] = nil
    }

    private func revealRecording(atPath path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// Shows the banner even while KnowingYou is frontmost (it never really
    /// is, being an accessory app, but this is what makes it show at all).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let requestID = userInfo["requestID"] as? String
        let audioPath = userInfo["audioPath"] as? String

        // Handling an action/reveal never needs to finish before telling the
        // system "done" — call it immediately rather than threading it
        // through the `Task`, which would require a non-Sendable closure to
        // cross the actor boundary.
        completionHandler()

        Task { @MainActor [weak self] in
            if let audioPath {
                self?.revealRecording(atPath: audioPath)
            } else if actionIdentifier != UNNotificationDismissActionIdentifier {
                self?.handleAction(identifier: actionIdentifier, requestID: requestID)
            }
        }
    }
}
