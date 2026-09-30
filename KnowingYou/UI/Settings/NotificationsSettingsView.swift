import SwiftUI

/// The 通知 (Notifications) page.
struct NotificationsSettingsView: View {
    @State private var notifyMeetingDetected = Preferences.shared.notifyMeetingDetected
    @State private var notifyMeetingEnded = Preferences.shared.notifyMeetingEnded
    @State private var notifyRecordingSaved = Preferences.shared.notifyRecordingSaved

    var body: some View {
        SettingsPageScaffold(title: "通知", lead: "什么时候提醒你。") {
            SettingsSection("通知") {
                SettingsRow(title: "会议开始提醒", subtitle: "会议开始时，主动询问是否开始录音", systemImage: "bell.badge") {
                    KYToggle(isOn: notifyMeetingDetectedBinding)
                }
                SettingsRow(title: "会议结束提醒", subtitle: "检测到会议结束并自动停止录音时通知我", systemImage: "stop.circle") {
                    KYToggle(isOn: notifyMeetingEndedBinding)
                }
                SettingsRow(title: "录音已保存提醒", subtitle: "录音文件写入完成后提醒我查看", systemImage: "checkmark.circle") {
                    KYToggle(isOn: notifyRecordingSavedBinding)
                }
            }
        }
    }

    private var notifyMeetingDetectedBinding: Binding<Bool> {
        Binding(
            get: { notifyMeetingDetected },
            set: { newValue in
                notifyMeetingDetected = newValue
                Preferences.shared.notifyMeetingDetected = newValue
            }
        )
    }

    private var notifyMeetingEndedBinding: Binding<Bool> {
        Binding(
            get: { notifyMeetingEnded },
            set: { newValue in
                notifyMeetingEnded = newValue
                Preferences.shared.notifyMeetingEnded = newValue
            }
        )
    }

    private var notifyRecordingSavedBinding: Binding<Bool> {
        Binding(
            get: { notifyRecordingSaved },
            set: { newValue in
                notifyRecordingSaved = newValue
                Preferences.shared.notifyRecordingSaved = newValue
            }
        )
    }
}

#Preview {
    NotificationsSettingsView()
        .frame(width: 540, height: 580)
}
