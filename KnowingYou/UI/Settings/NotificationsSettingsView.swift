import SwiftUI

/// The 通知 (Notifications) page: N1–N4. Rows are spaced 72pt apart here,
/// looser than the 60pt pitch used on the other pages — an intentional
/// difference called out in 02-ui-spec.md §6.
struct NotificationsSettingsView: View {
    @State private var notifyMeetingDetected = Preferences.shared.notifyMeetingDetected
    @State private var notifyMeetingEnded = Preferences.shared.notifyMeetingEnded
    @State private var notifyRecordingSaved = Preferences.shared.notifyRecordingSaved

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("通知")
            VStack(spacing: 12) {
                SettingsRow(title: "会议开始提醒", subtitle: "会议开始时，主动询问是否开始录音") {
                    KYToggle(isOn: notifyMeetingDetectedBinding)
                }
                SettingsRow(title: "会议结束提醒", subtitle: "检测到会议结束并自动停止录音时通知我") {
                    KYToggle(isOn: notifyMeetingEndedBinding)
                }
                SettingsRow(title: "录音已保存提醒", subtitle: "录音文件写入完成后提醒我查看") {
                    KYToggle(isOn: notifyRecordingSavedBinding)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
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
        .frame(width: 496, height: 520)
}
