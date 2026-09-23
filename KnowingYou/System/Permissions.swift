import AVFoundation
import AppKit
import CoreGraphics
import UserNotifications

/// Unified facade over the four TCC permissions this app needs. Screen
/// recording is queried/requested here but not onboarded until S18 (only
/// requested the first time the user clicks the screenshot-mark button).
@MainActor
@Observable
final class Permissions {
    static let shared = Permissions()

    /// Injected by S08: attempting to build a Process Tap is the only way to
    /// probe "系统音频录制" since there's no public query API for it.
    var systemAudioProbe: (@Sendable () async -> PermissionStatus)?

    func status(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .systemAudio:
            await systemAudioProbe?() ?? .notDetermined
        case .notifications:
            await Self.currentNotificationStatus()
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        }
    }

    func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .granted : .denied
        case .systemAudio:
            return await systemAudioProbe?() ?? .notDetermined
        case .notifications:
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                return granted ? .granted : .denied
            } catch {
                return .denied
            }
        case .screenRecording:
            return CGRequestScreenCaptureAccess() ? .granted : .denied
        }
    }

    func openSystemSettings(for permission: Permission) {
        guard let url = Self.systemSettingsURL(for: permission) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pure and testable on purpose (no NSWorkspace call) — see `PermissionsTests`.
    nonisolated static func systemSettingsURL(for permission: Permission) -> URL? {
        // "系统音频录制" and "屏幕录制" share the same TCC pane on modern macOS
        // (Privacy & Security > Screen & System Audio Recording); unverified
        // against a real System Settings window in this environment, see
        // S05's decision record.
        let anchor: String
        switch permission {
        case .microphone: anchor = "Privacy_Microphone"
        case .systemAudio: anchor = "Privacy_ScreenCapture"
        case .notifications: anchor = "Notifications"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    private nonisolated static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func currentNotificationStatus() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
