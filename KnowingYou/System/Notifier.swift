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

/// The app's user-facing prompts. "会议结束" is a system notification via
/// `UNUserNotificationCenter`; "检测到会议" and "录音已保存" are persistent
/// floating cards (`FloatingPromptPanel`), whose choices are routed back via
/// `onAction`.
@MainActor
final class Notifier: NSObject, MeetingNotifying {
    static let shared = Notifier()

    /// `MeetingCoordinator.start()` installs this to receive the user's choice
    /// on the meeting-detected prompt, keyed back to the `MeetingSignal` that
    /// triggered it.
    var onAction: ((NotificationAction, MeetingSignal) -> Void)?

    func registerCategories() {
        let meetingEnded = UNNotificationCategory(identifier: NotificationCategory.meetingEnded.rawValue, actions: [], intentIdentifiers: [], options: [])

        UNUserNotificationCenter.current().setNotificationCategories([meetingEnded])
        UNUserNotificationCenter.current().delegate = self
    }

    /// Shown as a persistent floating card under the menu bar rather than a
    /// system notification (which auto-dismisses and is easy to miss) — it
    /// stays until the user picks an action or closes it.
    func send(meetingDetected signal: MeetingSignal) {
        guard Preferences.shared.notifyMeetingDetected else { return }
        FloatingPromptPanel.shared.showMeetingDetected(appName: signal.app.displayNameKey) { [weak self] action in
            self?.onAction?(action, signal)
        }
    }

    func send(meetingEnded appDisplayName: String) {
        guard Preferences.shared.notifyMeetingEnded else { return }
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "%@会议已结束"), appDisplayName)
        content.categoryIdentifier = NotificationCategory.meetingEnded.rawValue
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Same persistent floating card as the meeting-detected prompt, with
    /// "拷贝路径" / "打开文件夹" instead of a system notification.
    func send(recordingSaved audioURL: URL) {
        guard Preferences.shared.notifyRecordingSaved else { return }
        FloatingPromptPanel.shared.showRecordingSaved(audioURL: audioURL)
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
        // The only remaining system notification ("会议已结束") has no actions.
        completionHandler()
    }
}
