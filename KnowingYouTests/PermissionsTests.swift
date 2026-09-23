import Testing
@testable import KnowingYou

struct PermissionsTests {
    @Test func systemSettingsURLsAreWellFormed() {
        for permission: Permission in [.microphone, .systemAudio, .notifications, .screenRecording] {
            let url = Permissions.systemSettingsURL(for: permission)
            #expect(url != nil, "expected a URL for \(permission)")
            #expect(url?.scheme == "x-apple.systempreferences")
        }
    }

    @Test func microphoneURLPointsAtMicrophonePane() {
        let url = Permissions.systemSettingsURL(for: .microphone)
        #expect(url?.absoluteString.contains("Privacy_Microphone") == true)
    }

    @Test func notificationsURLPointsAtNotificationsPane() {
        let url = Permissions.systemSettingsURL(for: .notifications)
        #expect(url?.absoluteString.contains("Notifications") == true)
    }

    @Test func systemAudioAndScreenRecordingShareAPane() {
        let systemAudio = Permissions.systemSettingsURL(for: .systemAudio)
        let screenRecording = Permissions.systemSettingsURL(for: .screenRecording)
        #expect(systemAudio == screenRecording)
    }
}
